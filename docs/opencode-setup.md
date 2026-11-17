# OpenCode setup: free model, guards, phone

OpenCode v2 is installed on the Mac (`opencode` v2.1.4 plus `OpenCode.app`). It runs on a free DeepSeek V4.1 Flash
model, so no account, card or API key is needed. One global config drives every client: the terminal, the desktop app
and a phone connected to the same server.

The config lives at `~/.config/opencode/opencode.json`, outside this repo, so it never carries a secret.

## Model

`opencode/deepseek-v4.1-flash-free` is the same DeepSeek V4.1 Flash family as the "Fast High" preset used elsewhere.
It is free for a limited time, its provider states zero retention and no training on your data, and it needs no
sign-in. No daily cap is published.

```bash
opencode run --model opencode/deepseek-v4.1-flash-free "Reply with exactly: OK"   # smoke test
opencode models | grep free                                                       # current free ids
```

Other free ids on the same tier: `glm-5.3-flash-free`, `mimo-v2.6-flash-free`, `nemotron-3-ultra-free`.
`/models` switches the current session only; the config default stays DeepSeek Flash.

## Config

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "opencode/deepseek-v4.1-flash-free",
  "default_agent": "build",
  "instructions": ["CLAUDE.md"],
  "permissions": [
    { "action": "read", "resource": "*.env", "effect": "ask" },
    { "action": "read", "resource": "*.env.*", "effect": "ask" },
    { "action": "shell", "resource": "git push *", "effect": "ask" },
    { "action": "shell", "resource": "supabase db push *", "effect": "ask" },
    { "action": "shell", "resource": "supabase db reset *", "effect": "ask" },
    { "action": "shell", "resource": "vercel --prod *", "effect": "ask" },
    { "action": "shell", "resource": "npm publish *", "effect": "ask" }
  ]
}
```

`instructions` matters here: OpenCode V2 reads `AGENTS.md` only and does not fall back to `CLAUDE.md`. A relative
entry is searched from the workspace up to the project root and skipped when missing, so this line loads the notes
index in this repo and does nothing in other projects.

## Guards

Rules are last-match-wins and every agent inherits them.

| Command | Effect |
| --- | --- |
| `git push` | ask |
| `supabase db push`, `supabase db reset` | ask |
| `vercel --prod` | ask |
| `npm publish` | ask |
| reading `.env`, `.env.*` | ask (`.env.example` stays readable) |

Approval prompts appear on whichever device is connected, so a phone tap can approve a production migration. `plan`
still cannot edit files; `build` is the default agent.

## Desktop

```bash
cd /Users/thetrungdo/Downloads/banbe
opencode                      # TUI with the default model
opencode run "explain the hold-seat flow"   # headless, one answer
open -a OpenCode              # desktop app, same sessions
```

## Phone

One-time server setup (already done on this Mac):

```bash
opencode service set password 'choose-a-strong-password'
opencode service set hostname 0.0.0.0     # needed for LAN access
opencode service set port 4097
opencode service restart
opencode service status                   # http://0.0.0.0:4097
ipconfig getifaddr en0                    # LAN address, e.g. 192.168.2.162
```

Port 4097 avoids 4096, which the Kilo VS Code extension holds on loopback. The desktop app owns this service:
change settings with `opencode service set ...`, then quit and reopen the app. Starting a second one with
`opencode service start` while the app is open is exactly what produces
`Managed service port ... is already in use`.

**A. Browser, no install.** Open `http://<lan-ip>:4097`, user `opencode`, password from
`cat ~/.config/opencode/service.json`. Full sessions, diffs and approvals; edits land on the Mac.

**B. Mobile app** (TestFlight on iOS, Play Store on Android). Run `opencode pair` in the repo, then scan the QR or
paste the link. Links work once and expire after five minutes, so generate one when the phone is in hand. Same Wi-Fi
only. Away from home: `opencode pair --remote` (OpenTunnel, asks before exposing the server) or Tailscale Serve, then
`opencode pair --url <machine>.tailnet-name.ts.net`.

Binding `0.0.0.0` is what makes LAN pairing work; the password is the only gate. Back to loopback on an untrusted
network:

```bash
opencode service set hostname 127.0.0.1 && opencode service restart
```

The phone drives this Mac. Sessions stop when the Mac sleeps or the service stops, so phone-only work needs an
always-on host instead.

## Verified 2026-11-17

- Free model answered with no sign-in, and the config default resolved without a `--model` flag.
- Service listens on `*:4097` (4096 belongs to Kilo), reachable over the LAN; `/api/*` returns 401 without the password.
- `opencode pair` printed a working one-time link and QR.

Not verified: the mobile app itself, a multi-file code edit on this model, and a permission prompt end to end.
