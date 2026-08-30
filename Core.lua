-- EllesmereUIGroupTargetFrame / Core.lua
--
-- Shared namespace, SavedVariables, dependency detection, run-state policy,
-- slash commands and debug output. This file owns policy (enabled / dormant /
-- deps present); GroupTargets.lua owns the secure target-frame presentation and
-- the hooks into EllesmereUIRaidFrames' party layout.
--
-- This is a standalone companion addon. It does NOT modify EllesmereUI or
-- EllesmereUIRaidFrames -- it reads their public module namespace and pixel-perfect
-- helper, and attaches its own secure frames beside the existing party buttons.
-- It is the standalone equivalent of the "Party Targets" feature proposed in
-- EllesmereUI PR #1510 (feature/party-target-frames).
--
-- Lua 5.1 only. No goto, no //, no native bitwise operators, no _ENV.

local ADDON, EGTF = ...

-- Cheap upvalues.
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown

------------------------------------------------------------------------------
-- SavedVariables defaults. Configuration ONLY. Visual styling (widths, colours,
-- fonts) is intentionally NOT stored here: it is read live from the
-- EllesmereUIRaidFrames profile so the target frames always match the party
-- frames. Only this addon's own toggle + relative sizing live here.
------------------------------------------------------------------------------

local DEFAULTS = {
    enabled     = true,   -- installing the addon is the opt-in; toggle with /egtf
    -- Target frames render smaller than their owner party button, mirroring
    -- EllesmereUI's Target vs Target-of-Target size convention (~0.56x width,
    -- ~0.55x height) so the party -> party-target pairing reads clearly.
    widthScale  = 0.56,
    heightScale = 0.55,
    debug       = false,
}

EGTF.DEFAULTS = DEFAULTS

------------------------------------------------------------------------------
-- Output helpers.
------------------------------------------------------------------------------

local PREFIX = "|cff0cd29f[GTF]|r "

function EGTF.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

function EGTF.Debug(msg)
    if EGTF.db and EGTF.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "|cff888888" .. tostring(msg) .. "|r")
    end
end

------------------------------------------------------------------------------
-- State.
------------------------------------------------------------------------------

EGTF.active = false   -- true only when enabled + deps present
EGTF.RF     = nil     -- cached EllesmereUIRaidFrames module namespace (ns)
EGTF.RFA    = nil     -- cached EllesmereUIRaidFrames Ace addon (owns .db)
EGTF.PP     = nil     -- cached EllesmereUI.PP (pixel-perfect helper)

-- Merges any missing default keys into the saved table (shallow + one nested
-- level). Keeps user edits, fills gaps after upgrades.
local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            for k2, v2 in pairs(v) do
                if dst[k][k2] == nil then dst[k][k2] = v2 end
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

------------------------------------------------------------------------------
-- Dependency detection. We integrate with the EllesmereUIRaidFrames party
-- header; if the suite is missing (or its party header has not been built yet)
-- we stay dormant instead of erroring.
------------------------------------------------------------------------------

local function DetectDeps()
    local EUI = _G.EllesmereUI
    EGTF.RF  = EUI and EUI._ModuleNS and EUI._ModuleNS["EllesmereUIRaidFrames"] or nil
    EGTF.RFA = _G.EllesmereUIRaidFrames or nil
    EGTF.PP  = EUI and EUI.PP or nil

    -- Ready only once the raid-frames module has actually built the party
    -- header (its child buttons are what we anchor to) and its profile exists.
    local ready = EGTF.RF and EGTF.RF._partyHeader
        and EGTF.RFA and EGTF.RFA.db and EGTF.RFA.db.profile and true or false
    return ready
end

EGTF.DetectDeps = DetectDeps

-- Live read of the EllesmereUIRaidFrames profile (visual source of truth).
function EGTF.Profile()
    return EGTF.RFA and EGTF.RFA.db and EGTF.RFA.db.profile or nil
end

-- Recompute whether the target frames should be running and flip them on/off
-- accordingly. Safe to call repeatedly.
function EGTF.Refresh()
    local shouldRun = EGTF.db and EGTF.db.enabled and DetectDeps() and true or false
    if shouldRun and not EGTF.active then
        EGTF.active = true
        EGTF.EnableTargets()   -- GroupTargets.lua
        EGTF.Debug("Group target frames enabled.")
    elseif (not shouldRun) and EGTF.active then
        EGTF.active = false
        EGTF.DisableTargets()  -- GroupTargets.lua
        EGTF.Debug("Group target frames disabled.")
    end
end

------------------------------------------------------------------------------
-- Slash commands.
------------------------------------------------------------------------------

local function PrintStatus()
    local db = EGTF.db
    EGTF.Print("Status: " .. (db.enabled and "|cff40ff40enabled|r" or "|cffff4040disabled|r")
        .. (EGTF.active and " (running)" or " (idle)"))
    EGTF.Print(string.format("Size: width=%.2fx height=%.2fx of party button.  debug=%s",
        db.widthScale, db.heightScale, tostring(db.debug)))
    if not DetectDeps() then
        EGTF.Print("|cffffcc00Waiting for EllesmereUI / EllesmereUIRaidFrames party frames.|r")
    end
end

local function PrintHelp()
    EGTF.Print("EllesmereUI - Group Target Frames commands:")
    EGTF.Print("  /egtf            - show status")
    EGTF.Print("  /egtf help       - this help")
    EGTF.Print("  /egtf enable     - show party target frames")
    EGTF.Print("  /egtf disable    - hide party target frames")
    EGTF.Print("  /egtf debug      - toggle debug messages")
    EGTF.Print("  /egtf reset      - restore default settings")
end

local function HandleSlash(msg)
    msg = msg or ""
    local cmd = (msg:match("^%s*(%S*)") or ""):lower()

    if cmd == "" then
        PrintStatus()
    elseif cmd == "help" then
        PrintHelp()
    elseif cmd == "enable" then
        EGTF.db.enabled = true
        EGTF.Refresh()
        EGTF.Print("Enabled.")
    elseif cmd == "disable" then
        EGTF.db.enabled = false
        EGTF.Refresh()
        EGTF.Print("Disabled.")
    elseif cmd == "debug" then
        EGTF.db.debug = not EGTF.db.debug
        EGTF.Print("Debug " .. (EGTF.db.debug and "ON" or "OFF") .. ".")
    elseif cmd == "reset" then
        wipe(EGTF.db)
        ApplyDefaults(EGTF.db, DEFAULTS)
        if EGTF.active and EGTF.Layout then EGTF.Layout() end
        EGTF.Print("Settings reset to defaults.")
    else
        PrintHelp()
    end
end

SLASH_ELLESMEREGTF1 = "/egtf"
SLASH_ELLESMEREGTF2 = "/grouptargets"
SlashCmdList["ELLESMEREGTF"] = HandleSlash

------------------------------------------------------------------------------
-- Boot / event wiring.
------------------------------------------------------------------------------

local function OnLogin()
    -- Install the layout hooks once (safe even while dormant; they no-op until
    -- EGTF.active). GroupTargets.lua owns them.
    if EGTF.InstallHooks then EGTF.InstallHooks() end

    -- Dependencies may finish loading a hair after us; retry a few times while
    -- the raid-frames module builds its party header.
    local tries = 0
    local function try()
        tries = tries + 1
        EGTF.Refresh()
        if not EGTF.active and EGTF.db.enabled and tries < 8 then
            C_Timer.After(1, try)
        end
    end
    try()
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("GROUP_ROSTER_UPDATE")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            EllesmereUIGroupTargetFrameDB = EllesmereUIGroupTargetFrameDB or {}
            EGTF.db = ApplyDefaults(EllesmereUIGroupTargetFrameDB, DEFAULTS)
        end
    elseif event == "PLAYER_LOGIN" then
        OnLogin()
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Deps may only become ready once you join a group (the party header is
        -- built lazily); keep the run-state coherent. No-op once active.
        if EGTF.db and EGTF.db.enabled and not EGTF.active and not InCombatLockdown() then
            EGTF.Refresh()
        end
    end
end)
