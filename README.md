# Tern: computer tools

Tern is a terminal for reaching your own computers from your iPhone. This repository publishes the tools that run
on the computers: `tern` and the `tern-cli` command-line tool.

- **`tern`** is one program with two jobs. In `~/.tern`, `tern-server` and `tern-connector` are links to it, and it
  does the job its name says:
  - as **`tern-server`** it runs your terminal sessions. Sessions keep running when your phone sleeps or changes
    networks, and you can pick them up again later;
  - as **`tern-connector`** it lets your phone reach this computer from other networks. It only dials out, so
    nothing on the computer is opened to the internet, and it lets in only the phones you allow.
- **`tern-cli`** is the command-line tool, for using Tern from another computer.

The Tern iPhone app can set these up for you over SSH. This repository is for installing them yourself.

## Reaching your computer from anywhere

The connector keeps an outbound connection to Tern Relay. When you connect from your phone, Tern Relay introduces
your phone and your computer to each other, and the session then runs directly between them. Tern Relay never sees
what you type; the session is end-to-end encrypted.

On some networks no direct path opens. Carrying the session through Tern Relay in that case is planned as a paid
option in a later release.

## Install

macOS (Apple silicon or Intel) and Linux (x86_64 or aarch64). No sudo; everything goes in `~/.tern`. On Linux,
the connector needs the system's trusted certificates (the `ca-certificates` package, present on most
distributions); `tern-install.sh --connector` checks for them.

```sh
curl -fsSL https://github.com/asaasinventuresllc/Tern/releases/latest/download/tern-install.sh | sh
```

To reach the computer from anywhere, also set up the connector and allow your phone:

```sh
curl -fsSL https://github.com/asaasinventuresllc/Tern/releases/latest/download/tern-install.sh | sh -s -- \
  --connector --allow <your phone's Tern key>
```

The connector then runs as a service for your login (a LaunchAgent on macOS, a systemd user service on Linux) and
prints this computer's endpoint id, which you add in the app.

Run `tern-install.sh --help` for every option. Running it again is safe.

## Remove

The easiest way is `tern-cli uninstall`. It shows what it will remove and asks first, then stops the connector and
deletes Tern's files from `~/.tern`. The phones you allowed are kept unless you add `--remove-access`, and
`--dry-run` only shows the plan. **Remove from Tern** in the app and `tern-install.sh --uninstall` do the same
removal.

## Checking what you download

Every release has a `SHA256SUMS` file. `tern-install.sh` checks every download against it before installing anything.
You can also require specific hashes with `--sha256 NAME=HASH`. To check by hand:

```sh
shasum -a 256 -c SHA256SUMS --ignore-missing
```

## Homebrew

```sh
brew install asaasinventuresllc/tern/tern-tools
```

This installs `tern` (with its `tern-server` and `tern-connector` links) and the `tern-cli` command-line tool into
Homebrew's `bin`. It installs the programs only: set up the connector with `tern-install.sh --connector` or from the
Tern app. Remove them with `brew uninstall tern-tools`.

## Licenses

`tern` (also run as `tern-server` and `tern-connector`) and the `tern-cli` command-line tool as published in this
repository's releases,
`tern-install.sh`, and the Homebrew formula for them are licensed under the Apache License, Version 2.0 (`LICENSE`).
`NOTICE` sets out that scope. It doesn't cover the Tern iPhone app, Tern Relay (the hosted relay service and its
server software), source code not published here, the Tern, Tern Relay and aSaaSin names and logos, or any other
aSaaSin product; those remain proprietary.

Third-party components and their licenses are listed in `THIRD_PARTY_NOTICES`, which ships with every release.
