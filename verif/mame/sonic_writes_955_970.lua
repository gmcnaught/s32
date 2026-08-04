-- Log EVERY maincpu write during frames 955-970, no address filter, to find
-- the actual instruction that populates the SegaSonic floor palette bank
-- (a targeted install_write_tap on just 0x607800-0x607cff produced zero
-- hits despite the value provably changing there, which needs explaining).

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
local first = tonumber(os.getenv("WIDE_FIRST")) or 955
local last = tonumber(os.getenv("WIDE_LAST")) or 970
local out_path = os.getenv("WIDE_OUT") or "scratch/mame_sonic_vram/wide_writes.txt"
local max_lines = tonumber(os.getenv("WIDE_MAX")) or 200000
local log = assert(io.open(out_path, "w"))

local frame = 0
local n = 0

_G.sonic_wide_tap = mem:install_write_tap(0x000000, 0xffffff, "wide_writes",
  function(offset, data, mask)
    if frame < first or frame > last then return end
    if offset < 0x600000 or offset > 0x6fffff then return end
    n = n + 1
    if n <= max_lines then
      log:write(string.format("f=%d pc=%08x a=%06x d=%04x mask=%04x\n",
        frame, cpu.state["PC"].value, offset, data & 0xffff, mask & 0xffff))
    end
  end)

_G.sonic_wide_driver = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if frame >= coin_at and frame < coin_at + coin_len then coin:set_value(1)
  elseif frame == coin_at + coin_len then coin:set_value(0) end
  if frame >= start_at and frame < start_at + start_len then start:set_value(1)
  elseif frame == start_at + start_len then start:set_value(0) end
  if frame >= last + 5 then
    log:write(string.format("# total palette-region writes=%d\n", n))
    log:close()
    log = nil
    machine:exit()
  end
end)

emu.add_machine_stop_notifier(function()
  if log then log:close(); log = nil end
end)
