-- EllesmereUIGroupTargetFrame / GroupTargets.lua
--
-- The secure target-frame presentation: a minimal clickable frame next to each
-- party member showing that member's current target (party1target..party4target).
-- Left-click targets that unit.
--
-- Design (ported from EllesmereUI PR #1510, adapted to run as an external addon):
--   * Zero cost while disabled: nothing here runs until EnableTargets(). No
--     frames, no events, no OnUpdate, no polling.
--   * Built lazily on first enable; disabling unregisters events and hides the
--     frames (secure ops are deferred out of combat).
--   * Taint-free click: each frame is a SecureUnitButton whose unit follows its
--     owner party button via useparent-unit + unitsuffix="target", so the
--     Blizzard secure handler resolves party<N>target at click time, in combat,
--     with no protected mutation by us. Visibility is owned by RegisterUnitWatch,
--     so the frame shows/hides itself as the target appears/disappears.
--   * Party-only: frames attach exclusively to the EllesmereUIRaidFrames party
--     header buttons. Raid frames are untouched.
--
-- Lua 5.1 only.

local ADDON, EGTF = ...

local CreateFrame        = CreateFrame
local UnitExists         = UnitExists
local UnitName           = UnitName
local InCombatLockdown   = InCombatLockdown
local RegisterUnitWatch  = RegisterUnitWatch
local UnregisterUnitWatch = UnregisterUnitWatch
local hooksecurefunc     = hooksecurefunc

------------------------------------------------------------------------------
-- State.
------------------------------------------------------------------------------

local frames        = {}     -- one secure frame per party header button
local ptEnabled     = false  -- currently-applied state
local ptDesired     = false  -- requested state (may differ while in combat)
local ptCreated     = false
local eventFrame    = nil     -- name-refresh event host (created on first enable)
local combatWatcher = nil
local hooksInstalled = false

EGTF._frames = frames

------------------------------------------------------------------------------
-- Helpers borrowed from / matching the EllesmereUIRaidFrames module.
------------------------------------------------------------------------------

-- Snap to the physical pixel grid via the raid-frames module helper (falls back
-- to identity if unavailable).
local function PixelSnap(v)
    local RF = EGTF.RF
    if RF and RF.PixelSnap then return RF.PixelSnap(v) end
    return v
end

-- Apply the EllesmereUI raid-frames font to a font string (name text).
local function ApplyFont(fs, size)
    if not (fs and fs.SetFont) then return end
    local EUI = _G.EllesmereUI
    local fontPath = (EUI and EUI.GetFontPath and EUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    fs:SetFont(fontPath, size, "")
end

------------------------------------------------------------------------------
-- Name refresh (visibility is handled by RegisterUnitWatch, not here).
------------------------------------------------------------------------------

-- Refresh one target frame's name from its owner button's live unit. The owner's
-- unit attribute is the party token the header currently holds, so appending
-- "target" mirrors the secure unitsuffix resolution used for clicks.
local function RefreshName(tf)
    if not (tf and tf._ptName) then return end
    local owner = tf._ptOwner
    local pu = owner and owner:GetAttribute("unit")
    if pu then
        local tu = pu .. "target"
        if UnitExists(tu) then
            tf._ptName:SetText(UnitName(tu) or "")
            return
        end
    end
    tf._ptName:SetText("")
end

local function RefreshAll()
    for i = 1, #frames do
        RefreshName(frames[i])
    end
end
EGTF.RefreshAll = RefreshAll

local function OnEvent(_, event, arg1)
    if not ptEnabled then return end
    if event == "UNIT_TARGET" then
        -- Small Raid mode can bind any raid index to a party button. Read the
        -- live owner so roster changes never leave a fixed token list stale.
        if not arg1 then return end
        for i = 1, #frames do
            local tf = frames[i]
            local owner = tf._ptOwner
            if owner and owner:GetAttribute("unit") == arg1 then
                RefreshName(tf)
            end
        end
    else
        RefreshAll()
    end
end

------------------------------------------------------------------------------
-- Layout: size and anchor the target frames beside their owner party buttons.
-- Secure frames cannot be moved in combat, so this is out-of-combat only. The
-- anchor is relative to the owner button, so it travels when the header re-sorts.
------------------------------------------------------------------------------

function EGTF.Layout()
    if not ptEnabled then return end
    if InCombatLockdown() then return end
    local s = EGTF.Profile()
    if not s then return end
    local db = EGTF.db
    local bw = PixelSnap((s.partyFrameWidth or s.frameWidth or 125) * (db.widthScale or 0.56))
    local bh = PixelSnap((s.partyFrameHeight or s.frameHeight or 60) * (db.heightScale or 0.55))
    local gap = PixelSnap(s.partyCellSpacing or s.cellSpacing or 2)
    for i = 1, #frames do
        local tf = frames[i]
        tf:SetSize(bw, bh)
        tf:ClearAllPoints()
        tf:SetPoint("LEFT", tf._ptOwner, "RIGHT", gap, 0)
    end
end

------------------------------------------------------------------------------
-- One-time construction of the secure target frames (one per party header
-- button). Called only from Apply, out of combat.
------------------------------------------------------------------------------

local function Create()
    if ptCreated then return end
    local RF = EGTF.RF
    local header = RF and RF._partyHeader
    if not header then return end
    local s = EGTF.Profile()
    if not s then return end
    local PP = EGTF.PP
    local LVL_TEXT = (RF and RF.LVL_TEXT) or 12
    ptCreated = true

    for i = 1, 5 do
        local owner = header[i]
        if owner then
            local tf = CreateFrame("Button", "EGTFPartyTarget" .. i, owner, "SecureUnitButtonTemplate")
            -- Secure unit resolution: follow the owner button's unit + "target".
            tf:SetAttribute("useparent-unit", true)
            tf:SetAttribute("unitsuffix", "target")
            -- Secure left-click targets the resolved unit (resolved at click time
            -- by the Blizzard handler, so it is correct in combat).
            tf:RegisterForClicks("AnyUp")
            tf:SetAttribute("*type1", "target")
            tf:Hide()  -- RegisterUnitWatch owns show/hide once enabled

            -- Background (reuses the party/raid background convention).
            local bg = tf:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            local c = s.customBgColor or { r = 0, g = 0, b = 0 }
            bg:SetColorTexture(c.r, c.g, c.b, (s.bgDarkness or 50) / 100)
            if PP then PP.DisablePixelSnap(bg) end
            tf._ptBg = bg

            -- Border (same 1px black convention as the power/dispel borders).
            local bdr = CreateFrame("Frame", nil, tf)
            bdr:SetAllPoints(tf)
            bdr:SetFrameLevel(tf:GetFrameLevel() + 8)
            if PP then PP.CreateBorder(bdr, 0, 0, 0, 1, 1) end
            tf._ptBorder = bdr

            -- Name text (matches the raid-frames font/level).
            local carrier = CreateFrame("Frame", nil, tf)
            carrier:SetAllPoints(tf)
            carrier:SetFrameLevel(tf:GetFrameLevel() + LVL_TEXT)
            local nameFS = carrier:CreateFontString(nil, "OVERLAY")
            ApplyFont(nameFS, s.nameSize or 10)
            nameFS:SetPoint("LEFT", tf, "LEFT", 3, 0)
            nameFS:SetPoint("RIGHT", tf, "RIGHT", -3, 0)
            nameFS:SetJustifyH("CENTER")
            nameFS:SetWordWrap(false)
            nameFS:SetTextColor(1, 1, 1, 1)
            tf._ptName = nameFS

            tf._ptOwner = owner
            -- Refresh the name the moment the unit watch shows the frame (the
            -- owner acquired a target). Live target switches are covered by the
            -- UNIT_TARGET handler; this is our own frame, so the hook is safe.
            tf:HookScript("OnShow", function(self) RefreshName(self) end)

            frames[#frames + 1] = tf
        end
    end
end

------------------------------------------------------------------------------
-- Reconcile the applied state to ptDesired. Out of combat only; if called in
-- combat it arms a one-shot combat-end watcher and returns.
------------------------------------------------------------------------------

local function Apply()
    if ptDesired == ptEnabled then return end
    if InCombatLockdown() then
        if not combatWatcher then
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function() Apply() end)
            combatWatcher = f
        end
        return
    end

    if ptDesired then
        Create()
        if not eventFrame then
            eventFrame = CreateFrame("Frame")
            eventFrame:SetScript("OnEvent", OnEvent)
        end
        eventFrame:RegisterEvent("UNIT_TARGET")
        eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
        eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        ptEnabled = true
        EGTF.Layout()
        for i = 1, #frames do RegisterUnitWatch(frames[i]) end
        RefreshAll()
    else
        if eventFrame then eventFrame:UnregisterAllEvents() end
        for i = 1, #frames do
            local tf = frames[i]
            UnregisterUnitWatch(tf)
            tf:Hide()
        end
        ptEnabled = false
    end
end

------------------------------------------------------------------------------
-- Layout hooks: EllesmereUIRaidFrames re-lays-out its party frames in
-- _LayoutPartyFrames and ReloadPartyFrames. We hook those (they are plain table
-- fields on the module namespace) so our frames re-anchor/re-size alongside the
-- party buttons. No-op unless enabled.
------------------------------------------------------------------------------

function EGTF.InstallHooks()
    if hooksInstalled then return end
    local RF = EGTF.RF
    if not RF then
        local EUI = _G.EllesmereUI
        RF = EUI and EUI._ModuleNS and EUI._ModuleNS["EllesmereUIRaidFrames"] or nil
        EGTF.RF = RF
    end
    if not RF then return end  -- retried later, once the module has loaded

    local function post() EGTF.Layout() end
    if type(RF._LayoutPartyFrames) == "function" then
        hooksecurefunc(RF, "_LayoutPartyFrames", post)
    end
    if type(RF.ReloadPartyFrames) == "function" then
        hooksecurefunc(RF, "ReloadPartyFrames", post)
    end
    hooksInstalled = true
    EGTF.Debug("Party layout hooks installed.")
end

------------------------------------------------------------------------------
-- Public entry points wired from Core.lua's run-state policy.
------------------------------------------------------------------------------

function EGTF.EnableTargets()
    EGTF.InstallHooks()
    ptDesired = true
    Apply()
end

function EGTF.DisableTargets()
    ptDesired = false
    Apply()
end
