-- Wide VRAM write census for the SegaSonic floor-tilemap divergence.  Taps
-- the whole 128 KiB VRAM window (0x300000-0x31ffff) during a bounded frame
-- range and buckets writes by 0x400-word page so the actual name-table
-- region in use can be found empirically instead of guessed.
--
-- Env: SONIC_COIN_AT/LEN, SONIC_START_AT/LEN (defaults match the gameplay
-- reference), VRAM_CENSUS_FIRST/LAST (frame window to log), VRAM_CENSUS_OUT.

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
local census_first = tonumber(os.getenv("VRAM_CENSUS_FIRST")) or 1000
local census_last = tonumber(os.getenv("VRAM_CENSUS_LAST")) or 1095
local out_path = os.getenv("VRAM_CENSUS_OUT") or "scratch/mame_sonic_vram/census.log"
local final_frame = census_last + 5
local log = assert(io.open(out_path, "w"))

local frame = 0
local pages = {}   -- 0x400-word bucket -> count
local first_write = {}

_G.sonic_vram_census_tap = mem:install_write_tap(0x300000, 0x31ffff, "vram_census",
  function(offset, data, mask)
    if frame < census_first or frame > census_last then return end
    local vram_word = (offset - 0x300000) >> 1   -- word index from VRAM base
    local page = vram_word >> 10                 -- 0x400-word (0x800-byte) buckets
    pages[page] = (pages[page] or 0) + 1
    local key = page
    if not first_write[key] then
      first_write[key] = string.format("f=%d pc=%08x a=%06x d=%04x",
        frame, cpu.state["PC"].value, offset, data & 0xffff)
    end
  end)

_G.sonic_vram_census_driver = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if frame >= coin_at and frame < coin_at + coin_len then coin:set_value(1)
  elseif frame == coin_at + coin_len then coin:set_value(0) end
  if frame >= start_at and frame < start_at + start_len then start:set_value(1)
  elseif frame == start_at + start_len then start:set_value(0) end
  if frame >= final_frame then
    log:write(string.format("# census frames %d..%d\n", census_first, census_last))
    local keys = {}
    for k in pairs(pages) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      log:write(string.format("page=%03x (bytes %06x-%06x) writes=%d first[%s]\n",
        k, 0x300000 + k * 0x800, 0x300000 + k * 0x800 + 0x7ff,
        pages[k], first_write[k]))
    end
    log:close()
    log = nil
    machine:exit()
  end
end)

emu.add_machine_stop_notifier(function()
  if log then log:close(); log = nil end
end)
