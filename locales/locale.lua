-- Initialise the Locales table so locale files can write into it
Locales = Locales or {}

-- Resolve the active locale after config and all locale files are loaded
CreateThread(function()
    -- Nothing to do here — T() is called lazily at runtime,
    -- so Config.locale is always available by then.
end)

-- ── T(key, ...) ──────────────────────────────────────────────────────────────
-- Translate a key for the current locale, falling back to English.
-- Any extra arguments are forwarded to string.format.
function T(key, ...)
    local locale = Config and Config.locale or 'en'
    local tbl    = Locales[locale] or Locales['en'] or {}
    local str    = tbl[key]

    -- Fall back to English when the key is missing in the active locale
    if str == nil and locale ~= 'en' then
        str = (Locales['en'] or {})[key]
    end

    if str == nil then
        return '??' .. key .. '??'
    end

    -- Only call string.format when args are actually supplied
    if select('#', ...) > 0 then
        return string.format(str, ...)
    end
    return str
end

-- ── TUI() ─────────────────────────────────────────────────────────────────────
-- Returns the 'ui' sub-table for the current locale (used by client.lua to
-- pass translation strings to the NUI JavaScript layer).
function TUI()
    local locale = Config and Config.locale or 'en'
    local tbl    = Locales[locale] or Locales['en'] or {}
    local ui     = tbl['ui']

    -- Merge with English so missing keys are always filled in
    if locale ~= 'en' then
        local en_ui = (Locales['en'] or {})['ui'] or {}
        if ui then
            -- copy missing keys from English into a fresh table
            local merged = {}
            for k, v in pairs(en_ui) do merged[k] = v end
            for k, v in pairs(ui)    do merged[k] = v end
            return merged
        end
        return en_ui
    end

    return ui or {}
end
