-- Air Rescue dual-PCB first-access census for MAME 0.289.
-- Read-only: taps return the observed value and never mutate machine state.
-- Events are ordered only inside each board's V60 domain. Callback arrival
-- order across boards is deliberately not part of the comparison contract.
local machine = manager.machine

local function find_device(tags)
	for _, tag in ipairs(tags) do
		local device = machine.devices[tag]
		if device then return device, tag end
	end
	error("missing device; tried " .. table.concat(tags, ", "))
end

local maincpu, main_tag = find_device({":mainpcb:maincpu"})
local subcpu, sub_tag = find_device({":subpcb:maincpu", ":slavepcb:maincpu"})
local output = assert(os.getenv("S32_ARESCUE_CENSUS_OUT"),
	"S32_ARESCUE_CENSUS_OUT is required")
local stop_frame = tonumber(os.getenv("S32_ARESCUE_CENSUS_FRAMES") or "20")
local bridge_limit = tonumber(os.getenv("S32_ARESCUE_CENSUS_BRIDGE_MAX") or "4096")
local log = assert(io.open(output, "w"))
local frame = 0
local scheduler_seq = 0

local boards = {
	main = { cpu = maincpu, tag = main_tag, mem = assert(maincpu.spaces["program"]),
		ordinal = 0, first = {}, bridge_events = 0 },
	sub = { cpu = subcpu, tag = sub_tag, mem = assert(subcpu.spaces["program"]),
		ordinal = 0, first = {}, bridge_events = 0 }
}

local ranges = {
	-- name, tap start/end, canonical base, implemented address mask
	{ "rom",          0x000000, 0x1fffff, 0x000000, 0x1fffff },
	{ "rom_alias",    0xf00000, 0xffffff, 0x100000, 0x0fffff },
	{ "work",         0x200000, 0x2fffff, 0x200000, 0x00ffff },
	{ "vram",         0x300000, 0x3fffff, 0x300000, 0x01ffff },
	{ "sprite_ram",   0x400000, 0x4fffff, 0x400000, 0x01ffff },
	{ "sprite_ctrl",  0x500000, 0x5fffff, 0x500000, 0x00000f },
	{ "palette",      0x600000, 0x60ffff, 0x600000, 0x00ffff },
	{ "mixer",        0x610000, 0x61007f, 0x610000, 0x00007f },
	{ "sound_shared", 0x700000, 0x7fffff, 0x700000, 0x001fff },
	{ "comm",         0x800000, 0x800fff, 0x800000, 0x000fff },
	{ "comm_ctrl",    0x801000, 0x801003, 0x801000, 0x000003 },
	{ "dual_bridge",  0x810000, 0x810fff, 0x810000, 0x000fff },
	{ "dual_id",      0x818000, 0x818003, 0x818000, 0x000003 },
	{ "dsp",          0xa00000, 0xa00007, 0xa00000, 0x000007 },
	{ "io",           0xc00000, 0xc0001f, 0xc00000, 0x00001f },
	{ "adc",          0xc00050, 0xc00057, 0xc00050, 0x000007 },
	{ "irq",          0xd00000, 0xd7ffff, 0xd00000, 0x00000f }
}

local function hex(value, width)
	return string.format("%0" .. width .. "x", value)
end

local function lanes(mask)
	local result = 0
	if (mask & 0x00ff) ~= 0 then result = result | 1 end
	if (mask & 0xff00) ~= 0 then result = result | 2 end
	return result
end

local function emit(board_name, region, base, address_mask, rw, address, data, mask, first)
	local board = boards[board_name]
	board.ordinal = board.ordinal + 1
	scheduler_seq = scheduler_seq + 1
	local lane_bits = lanes(mask)
	local masked = (data & mask) & 0xffff
	log:write(string.format(
		'{"schema":"s32-arescue-census-v1","board":"%s",' ..
		'"domain":"%s.v60","ordinal":%d,"scheduler_seq":%d,' ..
		'"frame":%d,"pc":"%s","event":"bus_complete","rw":"%s",' ..
		'"address":"%s","canonical_address":"%s","data":"%s",' ..
		'"lanes":%d,"mem_mask_raw":"%s","device":"%s","first":%s}\n',
		board_name, board_name, board.ordinal, scheduler_seq, frame,
		hex(board.cpu.state["PC"].value, 8), rw, hex(address, 6),
		hex(base + ((address - base) & address_mask), 6), hex(masked, 4), lane_bits,
		hex(mask, 8), region, first and "true" or "false"))
end

local function observe(board_name, region, base, address_mask, rw, address, data, mask)
	local board = boards[board_name]
	local lane_bits = lanes(mask)
	local key = region .. ":" .. rw .. ":" .. tostring(lane_bits)
	local is_bridge = region == "dual_bridge" or region == "dual_id"
	local is_first = board.first[key] == nil
	if is_first then board.first[key] = true end
	if is_first or (is_bridge and board.bridge_events < bridge_limit) then
		if is_bridge then board.bridge_events = board.bridge_events + 1 end
		emit(board_name, region, base, address_mask, rw, address, data, mask, is_first)
	end
	return data
end

for board_name, board in pairs(boards) do
	for index, range in ipairs(ranges) do
		local region, first_addr, last_addr, base, address_mask =
			range[1], range[2], range[3], range[4], range[5]
		-- More-specific windows overlap broad mirrors. Install those windows
		-- independently; MAME invokes the most-specific mapped handler, while
		-- these taps are observation-only and their names remain unique.
		local read_name = "s32_census_" .. board_name .. "_" .. index .. "_r"
		local write_name = "s32_census_" .. board_name .. "_" .. index .. "_w"
		_G[read_name] = board.mem:install_read_tap(first_addr, last_addr, read_name,
			function(offset, data, mask)
				return observe(board_name, region, base, address_mask, "R", offset, data, mask)
			end)
		_G[write_name] = board.mem:install_write_tap(first_addr, last_addr, write_name,
			function(offset, data, mask)
				return observe(board_name, region, base, address_mask, "W", offset, data, mask)
			end)
	end
end

log:write(string.format(
	'{"schema":"s32-arescue-census-v1","event":"header",' ..
	'"main_tag":"%s","sub_tag":"%s","stop_frame":%d,' ..
	'"ordering":"per-board-only","mask_polarity":"active-high"}\n',
	main_tag, sub_tag, stop_frame))

_G.s32_arescue_census_driver = emu.add_machine_frame_notifier(function()
	frame = frame + 1
	log:flush()
	if frame >= stop_frame then machine:exit() end
end)

emu.add_machine_stop_notifier(function()
	if log then
		log:write(string.format(
			'{"schema":"s32-arescue-census-v1","event":"done",' ..
			'"frame":%d,"main_ordinal":%d,"sub_ordinal":%d}\n',
			frame, boards.main.ordinal, boards.sub.ordinal))
		log:close()
		log = nil
	end
end)
