-- Deterministic SegaSonic the Hedgehog attract-mode reference capture.
-- No inputs are asserted.  The companion RTL run captures the same emulated
-- frame numbers so video state and key CPU-visible state can be compared.

local machine = manager.machine
local cpu = assert(machine.devices[":mainpcb:maincpu"])
local mem = assert(cpu.spaces["program"])
local video = machine.video

local out = os.getenv("SONIC_ATTRACT_TRACE") or
  "scratch/mame_sonic_attract/trace.log"
local log = assert(io.open(out, "w"))
local frame = 0
local default_frames =
  "120,240,360,480,600,900,1200,1500,1800,2100,2400,2700,3000"
local capture_frames = {}
local last_frame = 0
for value in string.gmatch(
    os.getenv("SONIC_ATTRACT_FRAMES") or default_frames, "%d+") do
  local requested = assert(tonumber(value))
  capture_frames[requested] = true
  last_frame = math.max(last_frame, requested)
end
assert(last_frame > 0, "SONIC_ATTRACT_FRAMES contains no frame numbers")

local function emit(kind)
  log:write(string.format(
    "[%s] frame=%d pc=%08x level_clear=%04x level=%04x " ..
    "status=%04x/%04x spr0=%04x vram=%04x\n",
    kind, frame, cpu.state["PC"].value,
    mem:read_u16(0x20e5c4), mem:read_u16(0x20f06e),
    mem:read_u16(0x20f0bc), mem:read_u16(0x20f0be),
    mem:read_u16(0x204000), mem:read_u16(0x203f40)))
  log:flush()
end

_G.sonic_attract_driver = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if capture_frames[frame] then
    emit("landmark")
    video:snapshot()
  end
  if frame >= last_frame then
    emit("done")
    machine:exit()
  end
end)

emu.add_machine_stop_notifier(function()
  if log then
    log:close()
    log = nil
  end
end)
