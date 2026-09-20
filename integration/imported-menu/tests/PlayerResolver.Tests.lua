local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("player_resolver_tests")

-- Covers Scripts/PlayerResolver.lua.
--
-- The whole point of this module is that FindAllOf is expensive, so the tests count
-- scans directly: a cache that quietly re-scans is the bug this module exists to fix,
-- and a cache that keeps serving a replaced pawn is worse than the cost it saves.

-- The parentheses matter: assert returns every argument it was given, so without
-- them the message would arrive as loadfile's mode parameter.
local path = (assert(arg[1], "Supply PlayerResolver.lua"))
local module = assert(loadfile(path))()

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function pawn(address)
    return { address = address, valid = true,
        IsValid = function(self) return self.valid end,
        GetAddress = function(self) return self.address end }
end

local function fixture()
    local world = { scans = 0, clock = 0 }
    world.pawn = pawn(1000)
    world.controller = { valid = true, isLocal = true, Pawn = world.pawn,
        IsValid = function(self) return self.valid end,
        GetAddress = function() return 900 end,
        IsPlayerController = function(self) return self.isLocal end }
    world.resolver = module.New({
        findAllOf = function(name)
            world.scans = world.scans + 1
            if name ~= "PlayerController" then return {} end
            return world.others or { world.controller }
        end,
        now = function() return world.clock end,
    })
    return world
end

test("resolves the local player and reports the pawn behind the controller", function()
    local world = fixture()
    assert(world.resolver.Player() == world.pawn)
    assert(world.resolver.Controller() == world.controller)
end)

test("scans once and then reuses, which is the entire purpose", function()
    local world = fixture()
    for _ = 1, 500 do assert(world.resolver.Player() == world.pawn) end
    assert(world.scans == 1, "expected a single scan, got " .. world.scans)
    assert(world.resolver.Stats().reuses == 499, world.resolver.Stats().reuses)
end)

test("skips a controller that is not the local player controller", function()
    local world = fixture()
    local foreign = { valid = true, Pawn = pawn(7777),
        IsValid = function(self) return self.valid end,
        GetAddress = function() return 7000 end,
        IsPlayerController = function() return false end }
    world.others = { foreign, world.controller }
    assert(world.resolver.Player() == world.pawn)
end)

test("accepts a controller that only answers IsLocalPlayerController", function()
    local world = fixture()
    local target = pawn(2222)
    world.others = { { valid = true, Pawn = target,
        IsValid = function(self) return self.valid end,
        GetAddress = function() return 2000 end,
        IsLocalPlayerController = function() return true end } }
    assert(world.resolver.Player() == target)
end)

test("re-resolves once the controller reports a different pawn", function()
    local world = fixture()
    assert(world.resolver.Player() == world.pawn)
    local replacement = pawn(3333)
    world.controller.Pawn = replacement
    assert(world.resolver.Player() == replacement, "a replaced pawn must not keep serving the old one")
    assert(world.scans == 2, "expected exactly one extra scan, got " .. world.scans)
end)

test("re-resolves once the cached pawn goes invalid", function()
    local world = fixture()
    world.resolver.Player()
    world.pawn.valid = false
    local replacement = pawn(4444)
    world.controller.Pawn = replacement
    assert(world.resolver.Player() == replacement)
end)

test("re-resolves once the cached controller goes invalid", function()
    local world = fixture()
    world.resolver.Player()
    world.controller.valid = false
    local replacementPawn = pawn(5555)
    world.others = { { valid = true, Pawn = replacementPawn,
        IsValid = function(self) return self.valid end,
        GetAddress = function() return 5000 end,
        IsPlayerController = function() return true end } }
    assert(world.resolver.Player() == replacementPawn)
end)

test("the backstop deadline forces a fresh look even while everything still looks valid", function()
    local world = fixture()
    world.resolver.Player()
    assert(world.scans == 1)
    world.clock = 2000
    world.resolver.Player()
    assert(world.scans == 2, "the revalidation backstop did not fire")
end)

test("invalidating makes the next caller pay for a fresh look", function()
    local world = fixture()
    world.resolver.Player()
    world.resolver.Invalidate()
    world.resolver.Player()
    assert(world.scans == 2)
end)

test("reports no player rather than an invalid one when nothing matches", function()
    local world = fixture()
    world.others = {}
    assert(world.resolver.Player() == nil)
    assert(world.resolver.Controller() == nil)
end)

test("a controller with no usable pawn is not cached as a hit", function()
    local world = fixture()
    world.controller.Pawn = nil
    assert(world.resolver.Player() == nil)
    world.controller.Pawn = world.pawn
    assert(world.resolver.Player() == world.pawn)
end)

test("survives a native call that throws instead of returning", function()
    local world = fixture()
    world.resolver.Player()
    world.controller.IsValid = function() error("native call failed") end
    -- The cached entry can no longer be trusted, so it must fall back rather than throw.
    local ok = pcall(world.resolver.Player)
    assert(ok, "a throwing native call must not escape the resolver")
end)

test("falls back to Controller when no PlayerController is returned", function()
    local world = fixture()
    local fallbackPawn = pawn(6666)
    local fallback = { valid = true, Pawn = fallbackPawn,
        IsValid = function(self) return self.valid end,
        GetAddress = function() return 6000 end,
        IsPlayerController = function() return true end }
    world.resolver = module.New({
        findAllOf = function(name)
            world.scans = world.scans + 1
            if name == "PlayerController" then return {} end
            return { fallback }
        end,
        now = function() return world.clock end,
    })
    assert(world.resolver.Player() == fallbackPawn)
end)

print(count .. " player resolver tests passed")
