-- Deterministic Air Rescue dual-PCB communication trace.
--
-- This observes both V60 address spaces without mutating either machine.  It
-- is the reference contract for the first peer-board RTL milestone: both
-- processors must execute, return board identities 0/1, and exchange the
-- earliest accepted transaction through 0x810000-0x810fff.
local machine = manager.machine

local function required_device(tags)
	for _, tag in ipairs(tags) do
		local device = machine.devices[tag]
		if device then return device, tag end
	end
	error("missing device; tried " .. table.concat(tags, ", "))
end

local maincpu, main_tag = required_device({":mainpcb:maincpu"})
-- MAME renamed this nested board from slavepcb to subpcb.  Accept both so a
-- trace remains reproducible across the two locally documented references.
local subcpu, sub_tag = required_device({":subpcb:maincpu", ":slavepcb:maincpu"})
local mainmem = assert(maincpu.spaces["program"])
local submem = assert(subcpu.spaces["program"])
local output = assert(os.getenv("S32_ARESCUE_DUAL_OUT"),
	"S32_ARESCUE_DUAL_OUT is required")
local log = assert(io.open(output, "w"))
local stop_frame = tonumber(os.getenv("S32_ARESCUE_DUAL_FRAMES") or "20")
local max_events = tonumber(os.getenv("S32_ARESCUE_DUAL_MAX_EVENTS") or "20000")
local frame = 0
local seq = 0

local function pc(cpu)
	return cpu.state["PC"].value
end

local function record(board, kind, offset, data, mask, cpu)
	if seq >= max_events then return data end
	seq = seq + 1
	log:write(string.format(
		"seq=%d board=%s frame=%d pc=%08x op=%s addr=%06x data=%04x mask=%08x\n",
		seq, board, frame, pc(cpu), kind, offset, data & 0xffff, mask))
	return data
end

_G.s32_ares_main_r = mainmem:install_read_tap(
	0x810000, 0x810fff, "s32_ares_main_r",
	function(offset, data, mask)
		return record("main", "R", offset, data, mask, maincpu)
	end)
_G.s32_ares_main_w = mainmem:install_write_tap(
	0x810000, 0x810fff, "s32_ares_main_w",
	function(offset, data, mask)
		return record("main", "W", offset, data, mask, maincpu)
	end)
_G.s32_ares_sub_r = submem:install_read_tap(
	0x810000, 0x810fff, "s32_ares_sub_r",
	function(offset, data, mask)
		return record("sub", "R", offset, data, mask, subcpu)
	end)
_G.s32_ares_sub_w = submem:install_write_tap(
	0x810000, 0x810fff, "s32_ares_sub_w",
	function(offset, data, mask)
		return record("sub", "W", offset, data, mask, subcpu)
	end)

_G.s32_ares_identity_main = mainmem:install_read_tap(
	0x818000, 0x818003, "s32_ares_identity_main",
	function(offset, data, mask)
		return record("main", "ID", offset, data, mask, maincpu)
	end)
_G.s32_ares_identity_sub = submem:install_read_tap(
	0x818000, 0x818003, "s32_ares_identity_sub",
	function(offset, data, mask)
		return record("sub", "ID", offset, data, mask, subcpu)
	end)

log:write(string.format("# main=%s sub=%s stop_frame=%d\n",
	main_tag, sub_tag, stop_frame))

_G.s32_ares_driver = emu.add_machine_frame_notifier(function()
	frame = frame + 1
	log:write(string.format("# frame=%d main_pc=%08x sub_pc=%08x\n",
		frame, pc(maincpu), pc(subcpu)))
	log:flush()
	if frame >= stop_frame then machine:exit() end
end)

emu.add_machine_stop_notifier(function()
	if log then
		log:write(string.format("# done frame=%d events=%d\n", frame, seq))
		log:close()
		log = nil
	end
end)
