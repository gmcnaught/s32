-- Poll one known SegaSonic floor-palette word every frame (no write tap) and
-- report the first frame it becomes nonzero, plus the PC at that instant.
-- Avoids install_write_tap entirely after a wide-range tap produced no
-- output for unexplained reasons.

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
local watch_addr = tonumber(os.getenv("PAL_WATCH_ADDR")) or 0x607802
local last_frame = tonumber(os.getenv("PAL_WATCH_LAST")) or 1000
local out_path = os.getenv("PAL_WATCH_OUT") or "scratch/mame_sonic_vram/pal_watch.log"
local log = assert(io.open(out_path, "w"))

local frame = 0
local seen_nonzero = false

_G.sonic_pal_watch_driver = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if frame >= coin_at and frame < coin_at + coin_len then coin:set_value(1)
  elseif frame == coin_at + coin_len then coin:set_value(0) end
  if frame >= start_at and frame < start_at + start_len then start:set_value(1)
  elseif frame == start_at + start_len then start:set_value(0) end

  local value = mem:read_u16(watch_addr)
  if value ~= 0 and not seen_nonzero then
    seen_nonzero = true
    log:write(string.format("first-nonzero f=%d pc=%08x a=%06x d=%04x\n",
      frame, cpu.state["PC"].value, watch_addr, value))
    log:flush()
  end
  if frame % 20 == 0 then
    log:write(string.format("poll f=%d a=%06x d=%04x\n", frame, watch_addr, value))
    log:flush()
  end

  if frame >= last_frame then
    if not seen_nonzero then
      log:write("NEVER became nonzero in this window\n")
    end
    log:close()
    log = nil
    machine:exit()
  end
end)

emu.add_machine_stop_notifier(function()
  if log then log:close(); log = nil end
end)
