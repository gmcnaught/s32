-- Poll mixer register $4E (blend-enable / palette write-both control,
-- CPU address 0x61004E) every frame around the SegaSonic floor palette
-- write burst (frames 961-963) to see if it's transiently set then cleared.

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
local last_frame = tonumber(os.getenv("MIX4E_LAST")) or 1000
local out_path = os.getenv("MIX4E_OUT") or "scratch/mame_sonic_vram/mix4e.log"
local log = assert(io.open(out_path, "w"))

local frame = 0
local prev = -1

_G.sonic_mix4e_driver = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if frame >= coin_at and frame < coin_at + coin_len then coin:set_value(1)
  elseif frame == coin_at + coin_len then coin:set_value(0) end
  if frame >= start_at and frame < start_at + start_len then start:set_value(1)
  elseif frame == start_at + start_len then start:set_value(0) end

  local value = mem:read_u16(0x61004e)
  if value ~= prev then
    log:write(string.format("f=%d $4E=%04x (&0x0880=%04x) pc=%08x\n",
      frame, value, value & 0x0880, cpu.state["PC"].value))
    log:flush()
    prev = value
  end

  if frame >= last_frame then
    log:close()
    log = nil
    machine:exit()
  end
end)

emu.add_machine_stop_notifier(function()
  if log then log:close(); log = nil end
end)
