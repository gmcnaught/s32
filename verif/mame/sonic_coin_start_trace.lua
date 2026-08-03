-- Deterministic SegaSonic rev. C coin -> start reference scenario.
-- The companion RTL run uses the same frame numbers.  This trace brackets
-- the level-load transition and records the protection-visible work-RAM
-- writes that must occur after Start.

local machine = manager.machine
local cpu = assert(machine.devices[":mainpcb:maincpu"])
local mem = assert(cpu.spaces["program"])
local svc = assert(machine.ioport.ports[":mainpcb:SERVICE12_A"])
local coin = assert(svc.fields["Coin 1"])
local start = assert(svc.fields["1 Player Start"])
local video = machine.video

local out = os.getenv("SONIC_TRACE_OUT") or
  "scratch/mame_sonic/sonic_coin_start_trace.log"
local log = assert(io.open(out, "w"))
local frame = 0
local coin_at = tonumber(os.getenv("SONIC_COIN_AT")) or 900
local coin_len = tonumber(os.getenv("SONIC_COIN_LEN")) or 30
local start_at = tonumber(os.getenv("SONIC_START_AT")) or 960
local start_len = tonumber(os.getenv("SONIC_START_LEN")) or 30
local end_at = tonumber(os.getenv("SONIC_END_AT")) or 1400
local landmarks = {
  [coin_at - 50] = true,
  [coin_at + coin_len] = true,
  [start_at] = true,
  [start_at + start_len] = true,
  [1100] = true,
  [1300] = true,
  [end_at] = true,
}

local function pc()
  return cpu.state["PC"].value
end

for name, field in pairs(svc.fields) do
  log:write(string.format("[field] name=%s mask=%02x\n", name, field.mask))
end

local function emit(kind, text)
  log:write(string.format("[%s] frame=%d pc=%08x %s\n", kind, frame, pc(), text or ""))
  log:flush()
end

local function state_line()
  return string.format(
    "cleared=%04x level=%04x status=%04x/%04x sprram=%04x vram=%04x",
    mem:read_u16(0x20e5c4), mem:read_u16(0x20f06e),
    mem:read_u16(0x20f0bc), mem:read_u16(0x20f0be),
    mem:read_u16(0x204000), mem:read_u16(0x203f40)) ..
    string.format(" service12=%02x", svc:read())
end

_G.sonic_level_tap = mem:install_write_tap(
  0x20e5c4, 0x20e5c5, "sonic_level_load", function(offset, data, mask)
    emit("level-write", string.format("addr=%06x data=%04x mask=%04x", offset, data, mask))
end)

_G.sonic_status_tap = mem:install_write_tap(
  0x20f06e, 0x20f0bf, "sonic_level_state", function(offset, data, mask)
    if offset == 0x20f06e or offset == 0x20f0bc or offset == 0x20f0be then
      emit("state-write", string.format(
        "addr=%06x data=%04x mask=%04x", offset, data, mask))
    end
end)

_G.sonic_credit_tap = mem:install_write_tap(
  0x20ac40, 0x20ac8f, "sonic_credit", function(offset, data, mask)
    if frame >= coin_at - 5 and frame <= start_at + start_len + 5 then
      emit("credit-write", string.format(
        "addr=%06x data=%04x mask=%04x", offset, data, mask))
    end
end)

_G.sonic_input_tap = mem:install_read_tap(
  0xc00000, 0xc0001f, "sonic_io", function(offset, data, mask)
    if data ~= 0xffff and
        frame >= coin_at - 5 and frame <= start_at + start_len + 5 then
      emit("input-read", string.format("addr=%06x data=%04x mask=%04x", offset, data, mask))
    end
end)

_G.sonic_driver = emu.add_machine_frame_notifier(function()
  frame = frame + 1

  if frame >= coin_at and frame < coin_at + coin_len then
    coin:set_value(1)
  elseif frame == coin_at + coin_len then
    coin:set_value(0)
  end

  if frame >= start_at and frame < start_at + start_len then
    start:set_value(1)
  elseif frame == start_at + start_len then
    start:set_value(0)
  end

  if landmarks[frame] then
    emit("landmark", state_line())
    video:snapshot()
  end

  if frame >= end_at then
    emit("done", state_line())
    manager.machine:exit()
  end
end)

emu.add_machine_stop_notifier(function()
  if log then
    log:close()
    log = nil
  end
end)
