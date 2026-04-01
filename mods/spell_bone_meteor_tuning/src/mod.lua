local SPELL_CONFIG = {
    light_burst = {
        damage = 60,
    },
    eternal_light_burst = {
        damage = 60,
    },
    lightning_channel = {
        damage = 30,
    },
    eternal_lightning_channel = {
        damage = 48,
    },
    chain_lightning = {
        damage = 62,
    },
    eternal_chain_lightning = {
        damage = 128,
    },
    bone_channel_i = {
        damage = 34,
    },
    bone_channel_ii = {
        damage = 72,
    },
    shroud_meteor = {
        damage = 160,
    },
    acid_bite = {
        damage = 90,
    },
    eternal_acid_bite = {
        damage = 160,
    },
    shroud_beam_channel = {
        damage = 74,
    },
    shock_wisp = {
        damage = 144,
    },
}

local MOD_NAME = "Spell Bone Meteor Tuning"
local DEFAULT_DAMAGE_DMG_MOD = 0.7
local DEFAULT_DISPLAYED_DAMAGE = {
    light_burst = 6,
    eternal_light_burst = 6,
    lightning_channel = 21,
    eternal_lightning_channel = 27,
    chain_lightning = 62,
    eternal_chain_lightning = 128,
    bone_channel_i = 17,
    bone_channel_ii = 36,
    shroud_meteor = 128,
    acid_bite = 70,
    eternal_acid_bite = 130,
    shroud_beam_channel = 54,
    shock_wisp = 114,
}

local TARGET_ITEMS = {
    ["9eec2a21-daca-433a-ba04-62ccfb45abac"] = {
        label = "Light Burst",
        default_damage = DEFAULT_DISPLAYED_DAMAGE.light_burst,
        base_dmg_mod = 0.2,
        config = SPELL_CONFIG.light_burst,
    },
    ["9260bc07-79c6-48a6-9b44-6f46210ea969"] = {
        label = "Eternal Light Burst",
        default_damage = DEFAULT_DISPLAYED_DAMAGE.eternal_light_burst,
        base_dmg_mod = 0.2,
        config = SPELL_CONFIG.eternal_light_burst,
    },
    ["de69fe61-9fb9-4073-b131-aead68e3b7eb"] = {
        label = "Lightning Channel",
        default_damage = DEFAULT_DISPLAYED_DAMAGE.lightning_channel,
        base_dmg_mod = 0.8,
        config = SPELL_CONFIG.lightning_channel,
    },
    ["654ac987-5b16-46df-8c61-c23affe9c66b"] = {
        label = "Eternal Lightning Channel",
        default_damage = DEFAULT_DISPLAYED_DAMAGE.eternal_lightning_channel,
        base_dmg_mod = 0.8,
        config = SPELL_CONFIG.eternal_lightning_channel,
    },
    ["4d0bab0f-27b3-4709-8699-d2ff4ec184f1"] = {
        label = "Chain Lightning",
        default_damage = DEFAULT_DISPLAYED_DAMAGE.chain_lightning,
        base_dmg_mod = 1.1,
        config = SPELL_CONFIG.chain_lightning,
    },
    ["d033d5d2-7fce-40fb-98dc-10f193aadc92"] = {
        label = "Eternal Chain Lightning",
        default_damage = DEFAULT_DISPLAYED_DAMAGE.eternal_chain_lightning,
        base_dmg_mod = 1.1,
        config = SPELL_CONFIG.eternal_chain_lightning,
    },
    ["f561e314-117d-463a-8dfe-491c3b263570"] = {
        label = "Bone Channel I",
        default_damage = DEFAULT_DISPLAYED_DAMAGE.bone_channel_i,
        config = SPELL_CONFIG.bone_channel_i,
    },
    ["d9137a0c-aba4-42fc-83d5-c5e8d5f8da1a"] = {
        label = "Bone Channel II",
        default_damage = DEFAULT_DISPLAYED_DAMAGE.bone_channel_ii,
        config = SPELL_CONFIG.bone_channel_ii,
    },
    ["1462f62d-1b1d-4509-ba6b-1ab52ea7bbff"] = {
        label = "Shroud Meteor",
        default_damage = DEFAULT_DISPLAYED_DAMAGE.shroud_meteor,
        config = SPELL_CONFIG.shroud_meteor,
    },
    ["3afcdfb3-3e5d-45b8-ab66-f914926ed6f8"] = {
        label = "Acid Bite",
        default_damage = DEFAULT_DISPLAYED_DAMAGE.acid_bite,
        base_dmg_mod = 0.9,
        config = SPELL_CONFIG.acid_bite,
    },
    ["c34f0da4-84e6-46b7-ba61-84cb2d11d97c"] = {
        label = "Eternal Acid Bite",
        default_damage = DEFAULT_DISPLAYED_DAMAGE.eternal_acid_bite,
        base_dmg_mod = 0.9,
        config = SPELL_CONFIG.eternal_acid_bite,
    },
    ["069e4bf5-a171-4b91-9c64-c705dfb0c4e1"] = {
        label = "Shroud Beam Channel",
        default_damage = DEFAULT_DISPLAYED_DAMAGE.shroud_beam_channel,
        config = SPELL_CONFIG.shroud_beam_channel,
    },
    ["b1bcf072-69f2-4fae-ad8e-f4c0c07463e6"] = {
        label = "Shock Wisp",
        default_damage = DEFAULT_DISPLAYED_DAMAGE.shock_wisp,
        base_dmg_mod = 1.2,
        config = SPELL_CONFIG.shock_wisp,
    },
}

local function safe_len(value)
    local ok, result = pcall(function()
        return #value
    end)

    if ok and type(result) == "number" then
        return result
    end

    return 0
end

local function try_get_field(value, field_name)
    local ok, result = pcall(function()
        return value[field_name]
    end)

    if ok then
        return result
    end

    return nil
end

local function get_variant_value(value)
    local wrapped_value = try_get_field(value, "$value")
    if wrapped_value ~= nil then
        return wrapped_value
    end

    wrapped_value = try_get_field(value, "value")
    if wrapped_value ~= nil then
        return wrapped_value
    end

    return value
end

local function normalize_string(value)
    local resolved = get_variant_value(value)
    if type(resolved) == "string" then
        return resolved
    end

    if resolved == nil then
        return nil
    end

    local ok, text = pcall(function()
        return tostring(resolved)
    end)

    if not ok or type(text) ~= "string" then
        return nil
    end

    if text == "nil" or text:match("^table:") or text:match("^userdata:") then
        return nil
    end

    return text
end

local function normalize_guid(value)
    local text = normalize_string(value)
    if not text then
        return nil
    end

    text = text:lower():gsub("[{}]", "")
    local guid = text:match("%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x")
    return guid or text
end

local function get_resource_guid(resource)
    local data = resource and resource.data

    return normalize_guid(try_get_field(data, "$guid"))
        or normalize_guid(try_get_field(data, "guid"))
        or normalize_guid(try_get_field(resource, "$guid"))
        or normalize_guid(try_get_field(resource, "guid"))
end

local function get_resources_by_possible_types(type_names)
    local type_count = safe_len(type_names)
    for index = 1, type_count do
        local type_name = type_names[index]
        local resources = game.assets.get_resources_by_type(type_name)
        if safe_len(resources) > 0 then
            return resources, type_name
        end
    end

    return {}, nil
end

local function patch_item_damage(item_data, target)
    if not item_data or not item_data.damageSetup then
        return false
    end

    local configured_damage = target and target.config and target.config.damage
    local default_damage = target and target.default_damage
    if type(configured_damage) ~= "number" or type(default_damage) ~= "number" or default_damage == 0 then
        return false
    end

    local base_dmg_mod = (target and target.base_dmg_mod) or DEFAULT_DAMAGE_DMG_MOD
    local desired_dmg_mod = base_dmg_mod * (configured_damage / default_damage)
    if item_data.damageSetup.dmgMod == desired_dmg_mod then
        return false
    end

    item_data.damageSetup.dmgMod = desired_dmg_mod

    print(string.format(
        "[%s] Patched %s: damage=%s dmgMod=%.6f",
        MOD_NAME,
        target.label,
        tostring(configured_damage),
        desired_dmg_mod
    ))

    return true
end

local function patch_item_infos()
    local resources, resource_type = get_resources_by_possible_types({
        "keen::ItemInfo",
        "ItemInfo",
    })
    local resource_count = safe_len(resources)
    local patched = 0

    if resource_count == 0 then
        print(string.format("[%s] Warning: ItemInfo resources not found", MOD_NAME))
        return 0
    end

    print(string.format("[%s] ItemInfo query type=%s count=%d", MOD_NAME, tostring(resource_type), resource_count))

    for index = 1, resource_count do
        local resource = resources[index]
        local guid = get_resource_guid(resource)
        local target = guid and TARGET_ITEMS[guid]

        if target then
            if patch_item_damage(resource.data, target) then
                patched = patched + 1
            end
        end
    end

    if patched == 0 then
        print(string.format("[%s] Warning: no target ItemInfo resources matched", MOD_NAME))
    end

    return patched
end

local function main()
    print(string.format("[%s] Initializing", MOD_NAME))

    local patched_items = patch_item_infos()

    print(string.format(
        "[%s] Done. patched_items=%d",
        MOD_NAME,
        patched_items
    ))
end

local ok, err = pcall(main)
if not ok then
    print(string.format("[%s] Error: %s", MOD_NAME, tostring(err)))
end
