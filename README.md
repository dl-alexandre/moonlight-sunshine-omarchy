# Moonlight Sunshine for Omarchy

This user plugin adds a Moonlight icon to the Omarchy bar. Click it to scan
the local network for Sunshine hosts, then choose **Stream**, **Apps**, or
**Pair** for a host. Hosts can be starred as favorites, edited in the popup,
and given one-click app buttons.

## Install

```bash
omarchy plugin add https://github.com/dl-alexandre/moonlight-sunshine-omarchy.git --enable
```

Moonlight must already be installed and available as `moonlight` on your
`PATH`. To remove the plugin:

```bash
omarchy plugin remove dev.alexandre.moonlight-sunshine --yes
```

The helper uses Sunshine's `_nvstream._tcp` mDNS advertisement and prefers an
IPv4 address when both IPv4 and IPv6 records are present. It keeps optional
friendly aliases in:

```text
~/.config/moonlight-sunshine/hosts.json
```

Discovery is bounded to 64 hosts and 256 KiB of mDNS output. The helper's
Quickshell snapshot is capped at 128 KiB before the bar reads it.

Useful terminal commands:

```bash
omarchy-moonlight-sunshine snapshot --wait 1.2
omarchy-moonlight-sunshine remember living-room 192.168.1.50 --app Desktop
omarchy-moonlight-sunshine remember living-room 192.168.1.50 --apps "Desktop, Steam" --favorite
omarchy-moonlight-sunshine set-app living-room Steam
omarchy-moonlight-sunshine favorite living-room on
omarchy-moonlight-sunshine connect living-room --preset Gaming
```

Profiles keep different addresses separate. The popup can create a profile by
cloning the current one, which is useful for LAN versus VPN addresses:

```bash
omarchy-moonlight-sunshine profile-add VPN --from-profile LAN
omarchy-moonlight-sunshine profile-select VPN
omarchy-moonlight-sunshine remember studio-mac 100.64.0.12 --profile VPN
```

Built-in streaming presets are **Gaming**, **Desktop**, **Low bandwidth**, and
**Remote Desktop** (1440p/60 with absolute mouse). Assign one as a host default
with `set-preset`:

```bash
omarchy-moonlight-sunshine set-preset living-room "Remote Desktop" --profile VPN
```

Create an additional preset with `preset-add`:

```bash
omarchy-moonlight-sunshine preset-add "Travel gaming" --profile VPN --resolution 1080 --fps 60 --bitrate 12000 --display-mode fullscreen --keep-awake
```

The plugin does not store pairing PINs. Pairing opens an Omarchy floating
terminal so the PIN can be entered interactively.

## License

MIT. See [LICENSE](LICENSE).
