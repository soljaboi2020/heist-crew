# Heist Crew mock runtime

A pure-Luau fake of the Roblox APIs the game uses, so whole heists can be played headless
(no Studio). Built up over v2.0 → v3.4; this is the copy that survives container rebuilds
(the working copy used to live only in /tmp/hcmock).

Run a driver:

    python3 tools/mock/bundle.py /tmp/_b.luau drv_chain.luau
    ~/.claude/bin/luau /tmp/_b.luau | grep -E "passed|FAIL|RUNTIME"

`bundle.py` inlines every `src/**/*.lua` plus `mock_types/core/game.luau` and the driver.

Main suites: drv_slice (Sunny's Mart) · drv_chain (villa/jewelry/bank goal chain, v3.4) ·
drv_eaudit (E-prompt clash audit, all 4 heists) · drv_rr_v3int · drv_tut · drv_maskup ·
drv_getaway · drv_client · drv_ping · drv_bots · drv_stars (slow, ~9 min).
Mock quirk: `triggerPrompt()` teleports the player +2 studs in Z first; use a local
fire-in-place helper (see drv_chain `fireAt`) near lasers.
