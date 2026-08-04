-- Ordered VRAM write trace for the SegaSonic floor name-table divergence.
-- Logs every write in [VRAM_TRACE_LO, VRAM_TRACE_HI] during
-- [VRAM_TRACE_FIRST, VRAM_TRACE_LAST] in the same field order as RTL's
-- tb_core_romboot [memtrace] line, so the two logs diff directly:
--   f=<frame> pc=<pc> a=<addr> d=<data> mask=<mask>

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
local trace_lo = tonumber(os.getenv("VRAM_TRACE_LO")) or 0x300000
local trace_hi = tonumber(os.getenv("VRAM_TRACE_HI")) or 0x304fff
local trace_first = tonumber(os.getenv("VRAM_TRACE_FIRST")) or 950
local trace_last = tonumber(os.getenv("VRAM_TRACE_LAST")) or 975
local out_path = os.getenv("VRAM_TRACE_OUT") or "scratch/mame_sonic_vram/name_trace.txt"
local final_frame = trace_last + 10
local log = assert(io.open(out_path, "w"))

local frame = 0

_G.sonic_vram_name_tap = mem:install_write_tap(trace_lo, trace_hi, "vram_name",
  function(offset, data, mask)
    if frame < trace_first or frame > trace_last then return end
    log:write(string.format("f=%d pc=%08x a=%06x d=%04x mask=%04x\n",
      frame, cpu.state["PC"].value, offset, data & 0xffff, mask & 0xffff))
  end)

_G.sonic_vram_name_driver = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if frame >= coin_at and frame < coin_at + coin_len then coin:set_value(1)
  elseif frame == coin_at + coin_len then coin:set_value(0) end
  if frame >= start_at and frame < start_at + start_len then start:set_value(1)
  elseif frame == start_at + start_len then start:set_value(0) end
  if frame >= final_frame then
    log:close()
    log = nil
    machine:exit()
  end
end)

emu.add_machine_stop_notifier(function()
  if log then log:close(); log = nil end
end)
