# focus-history

A macOS CLI that tracks which apps have focus. Runs as a background daemon and logs every app switch with timestamp, PID, and bundle ID.

## Install

Requires macOS and Xcode Command Line Tools (`xcode-select --install`).

```bash
./install.sh
```

This installs a launchd daemon that starts automatically on login.

## Usage

```bash
focus-history --history                     # print full history
focus-history --history --last 20           # last 20 entries
focus-history --history --since "2026-04-14" # filter by date
focus-history --status                      # check if daemon is running
focus-history --uninstall                   # stop and remove daemon
focus-history --clear                       # clear log file
```

You can also run it in the foreground (live output to terminal):

```bash
./focus-history
```

## Log file

History is saved to `~/.focus-history.log`. Auto-rotates at 10 MB.
