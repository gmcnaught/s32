-- Census WHEN MAME writes the SegaSonic floor palette bank (CPU address
-- 0x600000-0x607fff observed necessary; narrowed after the VRAM/palette diff
-- pinpointed idx 0x3c00-0x3e70).  Logs the first and last frame each 0x100
-- entry bucket is touched so the write timing can be reproduced/compared.

local machine = manager.machine
local cpu = assert(machine.devices[":mainpcb:maincpu"])
local mem = assert(cpu.spaces["program"])
local svc = assert(machine.ioport.ports[":mainpcb:SERVICE12_A"])
local coin = assert(svc.fields["Coin 1"])
local start = assert(svc.fields["1 Player Start"])

local coin_at = tonumber(os.getenv("SONIC_COIN_AT")) or 900
local coin_len = tonumber(os.getenv("SONIC_COIN_LEN")) or 30
local start_at = tonumber(os.getenv("SONIC_START_AT")) or 960
local start_len = tonumber(os.getenv("SONIC_START_LEN")) or 30
-- Palette RAM is mapped at 0x600000-0x60ffff and MIRRORED across bits 17-19
-- (map(0x600000,0x60ffff).mirror(0x0e0000) in segas32.cpp), so the same word
-- is reachable at 0x600000, 0x620000, 0x640000, ... 0x6e0000.  Scan the whole
-- aliased span and report the RAW address actually used.
local lo = tonumber(os.getenv("PAL_CENSUS_LO")) or 0x600000
local hi = tonumber(os.getenv("PAL_CENSUS_HI")) or 0x6fffff
local match_word_lo = tonumber(os.getenv("PAL_CENSUS_MATCH_LO")) or 0x7800
local match_word_hi = tonumber(os.getenv("PAL_CENSUS_MATCH_HI")) or 0x7cff
local last_frame = tonumber(os.getenv("PAL_CENSUS_LAST")) or 1000
local out_path = os.getenv("PAL_CENSUS_OUT") or "scratch/mame_sonic_vram/pal_census.log"
local log = assert(io.open(out_path, "w"))

local frame = 0
local first_frame, last_write_frame
local first_write_line, last_write_line
local count = 0

_G.sonic_pal_census_tap = mem:install_write_tap(lo, hi, "pal_census",
  function(offset, data, mask)
    local aliased = offset & 0xffff
    if aliased < match_word_lo or aliased > match_word_hi then return end
    count = count + 1
    local line = string.format("f=%d pc=%08x a=%06x aliased=%04x d=%04x",
      frame, cpu.state["PC"].value, offset, aliased, data & 0xffff)
    if not first_frame then
      first_frame = frame
      first_write_line = line
    end
    last_write_frame = frame
    last_write_line = line
  end)

_G.sonic_pal_census_driver = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if frame >= coin_at and frame < coin_at + coin_len then coin:set_value(1)
  elseif frame == coin_at + coin_len then coin:set_value(0) end
  if frame >= start_at and frame < start_at + start_len then start:set_value(1)
  elseif frame == start_at + start_len then start:set_value(0) end
  if frame >= last_frame then
    log:write(string.format("range %06x-%06x total_writes=%d\n", lo, hi, count))
    log:write(string.format("first: %s\n", first_write_line or "NONE"))
    log:write(string.format("last:  %s\n", last_write_line or "NONE"))
    log:close()
    log = nil
    machine:exit()
  end
end)

emu.add_machine_stop_notifier(function()
  if log then log:close(); log = nil end
end)
