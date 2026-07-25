# TrickleBar

A lightweight macOS menu bar download manager, backed by `aria2c`.

TrickleBar runs an `aria2c` daemon in the background and gives you a menu bar
popover to track active and completed downloads, plus a CLI that accepts a
subset of `aria2c`-compatible flags for easy migration.

## Features

- Menu bar popover showing active and completed downloads with progress,
  speed, and ETA
- Pause / resume / cancel / retry / remove per download
- Reveal completed files in Finder
- Failed downloads show error details and logs
- Settings for download directory, max concurrent downloads, and custom
  aria2c options
- Custom URL scheme (`tricklebar://add-download?url=<encoded>`) for adding
  downloads from other apps
- CLI usable as a drop-in for common `aria2c` invocations
- Single-instance enforcement; picks a random free port per instance

## Requirements

- macOS 13.0+
- Xcode command line tools (`swiftc`)
- `aria2c` (`brew install aria2`)

## Building

```sh
./build.sh
```

This compiles `Sources/*.swift` and packages `TrickleBar.app` at the repo
root, ad-hoc code signed. Set `ARCH` to build for a specific architecture
(`arm64` or `x86_64`); defaults to the host architecture.

## Usage

Launch the menu bar app:

```sh
open TrickleBar.app
```

Add downloads from the command line (the app must already be running):

```sh
TrickleBar.app/Contents/MacOS/TrickleBar https://example.com/file.zip
```

Optionally symlink it onto your `PATH`:

```sh
sudo ln -sf "$(pwd)/TrickleBar.app/Contents/MacOS/TrickleBar" /usr/local/bin/tricklebar
```

Then:

```sh
tricklebar https://example.com/file.zip
tricklebar -d ~/Downloads -o myfile.zip https://example.com/file.zip
tricklebar -i urls.txt
tricklebar --help
```

Run `tricklebar --help` for the full list of supported flags.

## Releases

Tagged pushes (`v*`) trigger a GitHub Actions workflow that builds
`arm64` and `x86_64` binaries and attaches them to a GitHub release.
