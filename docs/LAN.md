# MapSync LAN FoW sync (0.3.1-poc)

One-step retest: host explores → client minimap turns gray.

## Hotfix (0.3.1)

Previous build flooded the screen with on-screen status / HELLO spam (~1s), making the game unplayable. Fixed:
- On-screen overlay **off** by default (`EnableOnScreenStatus=false`)
- No `Status.set` / log spam on every HELLO
- HELLO interval 5s; quieter logs
- Better Host/Client detection via player authority

## On both PCs

1. Replace `ue4ss\Mods\MapSync` with this branch’s `Mods/MapSync`.
2. Run the prebuilt bridge:

```bat
tools\lan_bridge\lan_bridge.exe
```

3. Steam co-op → world → **F7** once.
4. Host explores. Client minimap should go gray.
5. Optional: **F8** toggles on-screen status (off by default). **F9** dumps LAN counters to the log only.

## If role stays Unknown

In `config.lua` set on each PC:

```lua
ForceLanRole = "Host"   -- session host
-- or
ForceLanRole = "Client" -- joiner
```

## If it fails

Send only `[MapSync][FoW]` / `[MapSync][LAN]` lines from both `UE4SS.log` files.
