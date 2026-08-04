-- Count SegaSonic sound-CPU activity during attract so the RTL sound chain has
-- a behavioural target.  Taps the Z80's I/O space (YM3438 at 0x80/0x90, bank
-- registers at 0xa0/0xb0, IRQ control at 0xd0) and its program-space writes to
-- the RF5C68 window, then reports totals at fixed frames.  No inputs are used.

local machine = manager.machine
local sound = assert(machine.devices[":mainpcb:soundcpu"])
local io_space = assert(sound.spaces["io"])
local program = assert(sound.spaces["program"])

local out = os.getenv("SONIC_SOUND_TRACE") or "scratch/mame_sonic_sound/trace.log"
local log = assert(io.open(out, "w"))

local last_frame = tonumber(os.getenv("SONIC_SOUND_FRAMES") or "900")
local counts = { fm1 = 0, fm2 = 0, bank_lo = 0, bank_hi = 0, irqctl = 0,
                 rf_reg = 0, rf_ram = 0 }
local frame = 0

-- Pin the tap handles in _G: Lua GC silently removes them otherwise.
_G.sonic_io_tap = io_space:install_write_tap(0x00, 0xff, "sonic_io", function(offset, data, mask)
  local port = offset & 0xff
  local high = port & 0xf0
  if high == 0x80 then counts.fm1 = counts.fm1 + 1
  elseif high == 0x90 then counts.fm2 = counts.fm2 + 1
  elseif high == 0xa0 then counts.bank_lo = counts.bank_lo + 1
  elseif high == 0xb0 then counts.bank_hi = counts.bank_hi + 1
  elseif high == 0xd0 then counts.irqctl = counts.irqctl + 1
  end
  return data
end)

-- RF5C68 occupies 0xd000-0xdfff in the sound CPU's program map: 0xd000-0xdfff
-- with bit 12 selecting the sample RAM window over the register file.
_G.sonic_pcm_tap = program:install_write_tap(0xd000, 0xdfff, "sonic_pcm", function(offset, data, mask)
  if (offset & 0x1000) ~= 0 then counts.rf_ram = counts.rf_ram + 1
  else counts.rf_reg = counts.rf_reg + 1 end
  return data
end)

local function emit(kind)
  log:write(string.format(
    "[%s] frame=%d fm1=%d fm2=%d bank=%d/%d irqctl=%d rf_reg=%d rf_ram=%d\n",
    kind, frame, counts.fm1, counts.fm2, counts.bank_lo, counts.bank_hi,
    counts.irqctl, counts.rf_reg, counts.rf_ram))
  log:flush()
end

_G.sonic_sound_driver = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if frame % 100 == 0 then emit("mark") end
  if frame >= last_frame then
    emit("done")
    machine:exit()
  end
end)

emu.add_machine_stop_notifier(function()
  if log then log:close(); log = nil end
end)
