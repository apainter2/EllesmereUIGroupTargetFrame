# EllesmereUI - Group Target Frames (`EllesmereUIGroupTargetFrame`)

A small, combat-safe companion add-on for **World of Warcraft Retail — Midnight 12.1.x**
(Lua 5.1) that adds, next to each **party** member on your **EllesmereUI** party
frames, a small clickable frame showing **that member's current target**.

```
[ Party member ][ their target ]   ← left-click the target frame to select it
```

Left-click a target frame to target that unit. It works in combat with no taint,
because the click is resolved by Blizzard's secure handler — this add-on never
performs a protected action on your behalf.

It integrates with **EllesmereUIRaidFrames** (the module that owns EllesmereUI's
party and raid frames). It **does not** modify EllesmereUI or EllesmereUIRaidFrames;
it reads their public module namespace and attaches its own secure frames beside
the existing party buttons.

This is the standalone equivalent of the *Party Targets* feature proposed in
EllesmereUI PR [#1510](https://github.com/EllesmereGaming/EllesmereUI/pull/1510)
(`feature/party-target-frames`). Packaging it as its own add-on lets you run the
feature while that PR is under review, with no changes to the EllesmereUI suite.

<img width="283" height="399" alt="636854766-d2f2c244-03e9-4c60-861a-797a8e92a606" src="https://github.com/user-attachments/assets/e45f6d0b-a488-487b-92a6-de56a8cfae55" />

---

## How it works (and why it is taint-free)

Each target frame is a `SecureUnitButton` created beside its owner party button.
Instead of storing a fixed unit, it **follows its owner**:

```
tf:SetAttribute("useparent-unit", true)   -- take the owner button's unit ...
tf:SetAttribute("unitsuffix", "target")    -- ... and append "target"
tf:SetAttribute("*type1", "target")        -- left-click => target that unit
```

So when the party header holds `party2` in that slot, the frame resolves
`party2target` — evaluated by Blizzard **at click time**, in combat, with no
protected mutation by this add-on.

* **Visibility** is owned by `RegisterUnitWatch`: the frame shows/hides itself as
  the member's target appears/disappears. No `OnUpdate`, no polling.
* **Name text** is refreshed only on the relevant events
  (`UNIT_TARGET` filtered to owner units, `UNIT_NAME_UPDATE`,
  `GROUP_ROSTER_UPDATE`, `PLAYER_ENTERING_WORLD`).
* **Layout** (size/anchor) runs out of combat only, and re-runs whenever
  EllesmereUIRaidFrames re-lays-out its party frames (via `hooksecurefunc` on its
  `_LayoutPartyFrames` / `ReloadPartyFrames`). The anchor is relative to the owner
  button, so the target frame travels automatically when the header re-sorts.
* **Party-only.** Frames attach exclusively to the EllesmereUIRaidFrames party
  header buttons. Raid frames are untouched.

Visual styling (width, height, background colour, font) is read **live** from the
EllesmereUIRaidFrames profile so the target frames always match your party frames.
Target frames render smaller than their owner button (~0.56x width, ~0.55x height),
mirroring EllesmereUI's Target vs Target-of-Target size convention.

---

## Integration points used

### Version 0.1.1

- Updated target-name refresh for EllesmereUI v9.1.8's Party Frames in Small Raids mode.
- Target-change events now match each displayed button's current owner unit,
  including raid indices above five and units reassigned after roster changes.
- Lua 5.1 syntax and focused event-handler checks passed. In-game testing is still required.

Determined by reading the [EllesmereGaming/EllesmereUI](https://github.com/EllesmereGaming/EllesmereUI)
source (module `EllesmereUIRaidFrames`), not from assumptions.

| Used | Source |
| --- | --- |
| Module namespace registry: `EllesmereUI._ModuleNS["EllesmereUIRaidFrames"]` | `EllesmereUIRaidFrames/EllesmereUIRaidFrames.lua` |
| Party header + pre-created buttons: `ns._partyHeader[1..5]` | same |
| Pixel snapping: `ns.PixelSnap`; text level: `ns.LVL_TEXT` | same |
| Layout hooks: `ns._LayoutPartyFrames`, `ns.ReloadPartyFrames` | same |
| Visual profile: `EllesmereUIRaidFrames.db.profile` | same |
| Pixel-perfect borders: `EllesmereUI.PP` | EllesmereUI core |

> **Note on coupling.** Unlike EllesmereUI companion add-ons that ride a stable,
> documented public API, this feature leans on the raid-frames module's *internal*
> party layout. It is designed to fail safe (it stays dormant if the party header
> is missing), but a future refactor of EllesmereUIRaidFrames could require an
> update here.

---

## Requirements

* **RequiredDeps:** `EllesmereUI`, `EllesmereUIRaidFrames`
* Interface: 120000 / 120001 / 120005 / 120007 / 120100

If either dependency is missing (or the party header has not been built yet), the
add-on stays dormant and prints nothing.

---

## Slash commands

```
/egtf              show status
/egtf help         command help
/egtf enable       show party target frames
/egtf disable      hide party target frames
/egtf debug        toggle debug messages
/egtf reset        restore default settings
```

`/grouptargets` is an alias for `/egtf`.

---

## Files

| File | Responsibility |
| --- | --- |
| `EllesmereUIGroupTargetFrame.toc` | Add-on manifest, deps, SavedVariables |
| `Core.lua` | SavedVariables, dependency detection, run-state policy, slash commands |
| `GroupTargets.lua` | Secure target-frame creation, layout, events, hooks |

SavedVariable: `EllesmereUIGroupTargetFrameDB` (configuration only — the enable
toggle and relative sizing; no unit data).
