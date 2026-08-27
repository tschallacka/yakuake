# AGENTS.md

Local notes for this checkout. Not committed upstream — this is KDE's repo, and
`AGENTS.md` is listed in `.git/info/exclude` alongside `flake.nix`.

## Building

`flake.nix` is untracked (local exclude), so a bare `nix build` fails with
"Path 'flake.nix' … is not tracked by Git". Build from the path instead:

```bash
nix build 'path:/home/mdibbets/git/yakuake'
```

The flake filters `.codegraph`, `.direnv` and `result` out of the source — the
CodeGraph index holds a unix socket nix cannot copy.

## Installing this checkout as the global yakuake

Installs into `/usr/local`, which precedes `/usr/bin` in both your PATH and
`XDG_DATA_DIRS` — including in the systemd **user** manager that runs the
autostart unit. The Ubuntu package (`yakuake` 25.12.3) is left untouched as a
fallback.

**1. Build and pin against nix GC.** The store path must survive garbage
collection; the repo's own `result` symlink is a gcroot but moves on every
rebuild, so keep a stable one:

```bash
nix build 'path:/home/mdibbets/git/yakuake' \
  --out-link ~/.local/state/nix-gcroots/yakuake-global
```

**2. Back up the shared KDE config first.** The dev build is a newer yakuake
against the same profile and rewrites these — see the
`yakuake-dev-build-shares-real-kde-config` memory:

```bash
B=~/.config/yakuake-preglobal-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$B/konsole"
cp -av ~/.config/yakuakerc ~/.config/kglobalshortcutsrc "$B"/
cp -av ~/.local/share/kxmlgui5/konsole/*.rc "$B/konsole/"
```

**3. Install (the sudo step).**

```bash
sudo install -d /usr/local/bin /usr/local/share/dbus-1/services \
&& sudo ln -sfn ~/.local/state/nix-gcroots/yakuake-global/bin/yakuake /usr/local/bin/yakuake \
&& printf '[D-BUS Service]\nName=org.kde.yakuake\nExec=/usr/local/bin/yakuake\n' \
   | sudo tee /usr/local/share/dbus-1/services/org.kde.yakuake.service >/dev/null
```

The D-Bus service file is not optional: the packaged one hardcodes
`/usr/bin/yakuake`, so without an override D-Bus activation still starts the
old build. It points at `/usr/local/bin/yakuake` rather than a store path, so
only the symlink needs updating after a rebuild.

**4. Swap the running instance.** Kill it — do not `systemctl --user stop`,
which lets yakuake save its in-memory config over whatever is on disk. systemd
restarts `app-org.kde.yakuake@autostart.service` within ~1s:

```bash
pkill -KILL yakuake
```

### After a later rebuild

Only step 1 again — re-pin the out-link. The `/usr/local` symlink follows it;
no sudo needed a second time.

### Rollback

```bash
sudo rm /usr/local/bin/yakuake /usr/local/share/dbus-1/services/org.kde.yakuake.service
```

If shortcuts go blank afterwards, stop yakuake, restore the backup from step 2,
then restart `plasma-kglobalaccel.service`.

### Notes

- Skins, icons and translations need no copying: the Qt wrapper prefixes the
  build's own `share` onto `XDG_DATA_DIRS`.
- Smoke-test a build without touching the real profile by pointing
  `XDG_CONFIG_HOME` and `XDG_DATA_HOME` at a throwaway directory:
  `XDG_CONFIG_HOME=/tmp/x/cfg XDG_DATA_HOME=/tmp/x/data result/bin/yakuake --version`

### If it still starts the packaged build

Editing `Exec=` in `org.kde.yakuake.desktop` does **nothing**. The entry sets
`DBusActivatable=true`, so launching goes through D-Bus activation and the
binary is chosen by the `.service` file, not the `.desktop`. Two places have to
be corrected, and neither is the one you would reach for first.

**1. The session bus has not re-read the override.** `dbus-daemon` cannot watch
a directory that did not exist when the session started, so the freshly created
`/usr/local/share/dbus-1/services/` is invisible until told:

```bash
dbus-send --session --print-reply --dest=org.freedesktop.DBus \
  / org.freedesktop.DBus.ReloadConfig
```

Only needed once, for the session in which the install happened — at next login
the bus scans `XDG_DATA_DIRS`, where `/usr/local/share` already leads.

**2. The autostart unit has the old path baked in.** The XDG autostart entry
ships `Exec=yakuake`, which `systemd-xdg-autostart-generator` resolves to an
absolute path *at generation time*, producing
`ExecStart=:/usr/bin/yakuake`. Make it explicit:

```bash
sed -i 's|^Exec=yakuake$|Exec=/usr/local/bin/yakuake|' \
  ~/.config/autostart/org.kde.yakuake.desktop
systemctl --user daemon-reload
```

Verify with `systemctl --user cat app-org.kde.yakuake@autostart.service`.

**Checking which binary is actually live.** `pgrep -x yakuake` finds nothing —
the nix wrapper execs `.yakuake-wrapped`, so `comm` is `.yakuake-wrappe`. Follow
the exe link instead:

```bash
ps -eo pid,comm,args --no-headers | awk '/yakuake/'
readlink -f /proc/<pid>/exe   # must land in /nix/store/...-yakuake-26.11.70
```
