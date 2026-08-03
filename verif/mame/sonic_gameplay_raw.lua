-- Deterministic SegaSonic coin/start gameplay reference using the raw
-- screen_device::pixels() surface.  This mirrors tb_core_romboot plusargs:
-- +COINAT=900 +COINLEN=30 +STARTAT=960 +STARTLEN=30.

local machine = manager.machine
local screen = assert(machine.screens[":mainpcb:screen"])
local cpu = assert(machine.devices[":mainpcb:maincpu"])
local mem = assert(cpu.spaces["program"])
local service = assert(machine.ioport.ports[":mainpcb:SERVICE12_A"])
local p1_port = assert(machine.ioport.ports[":mainpcb:P1_A"])
local coin = assert(service.fields["Coin 1"])
local start = assert(service.fields["1 Player Start"])
local button1 = assert(p1_port.fields["P1 Button 1"])
local track_x = assert(machine.ioport.ports[":mainpcb:TRACKX1"].fields["Trackball X"])
local track_y = assert(machine.ioport.ports[":mainpcb:TRACKY1"].fields["Trackball Y"])
local output_dir = assert(os.getenv("S32_RAW_DIR"), "S32_RAW_DIR is required")
local state_path = os.getenv("S32_RAW_TRACE") or (output_dir .. "/reference_state.jsonl")
local state = assert(io.open(state_path, "w"))
local coin_at = tonumber(os.getenv("SONIC_COIN_AT")) or 900
local coin_len = tonumber(os.getenv("SONIC_COIN_LEN")) or 30
local start_at = tonumber(os.getenv("SONIC_START_AT")) or 960
local start_len = tonumber(os.getenv("SONIC_START_LEN")) or 30
local final_frame = tonumber(os.getenv("SONIC_END_AT")) or 1400
local button_at = tonumber(os.getenv("SONIC_BUTTON_AT")) or 1000
local button_len = tonumber(os.getenv("SONIC_BUTTON_LEN")) or 10
local track_at = tonumber(os.getenv("SONIC_TRACK_AT")) or 1100
local track_len = tonumber(os.getenv("SONIC_TRACK_LEN")) or 200
local action_at = tonumber(os.getenv("SONIC_ACTION_AT")) or -1
local action_end = tonumber(os.getenv("SONIC_ACTION_END")) or action_at
local action_period = tonumber(os.getenv("SONIC_ACTION_PERIOD")) or 60
local action_len = tonumber(os.getenv("SONIC_ACTION_LEN")) or 5
local track_dx = tonumber(os.getenv("SONIC_TRACK_DX")) or 6
local track_dy = tonumber(os.getenv("SONIC_TRACK_DY")) or 2
local dump_state_at = tonumber(os.getenv("S32_DUMP_STATE_AT")) or -1
local event_path = os.getenv("S32_RAW_EVENTS") or (output_dir .. "/reference_trace.jsonl")
local events = assert(io.open(event_path, "w"))
local mixer_trace_path = os.getenv("S32_MIXER_TRACE")
local mixer_trace = mixer_trace_path and assert(io.open(mixer_trace_path, "w")) or nil
local vram_trace_path = os.getenv("S32_VRAM_TRACE")
local vram_trace = vram_trace_path and assert(io.open(vram_trace_path, "w")) or nil
local vram_trace_first = tonumber(os.getenv("S32_VRAM_TRACE_FIRST")) or 0
local vram_trace_last = tonumber(os.getenv("S32_VRAM_TRACE_LAST")) or final_frame
local captures = {}
for value in string.gmatch(
        os.getenv("S32_RAW_FRAMES") or "900,930,960,990,1100,1200,1300,1380", "%d+") do
    captures[assert(tonumber(value))] = true
end
local frame = 0

_G.s32_sonic_track_read = mem:install_read_tap(
    0xc00040, 0xc00047, "s32_sonic_track_read", function(offset, data, mask)
        if frame >= track_at - 5 and frame <= track_at + track_len + 5 then
            events:write(string.format(
                '{"frame":%d,"cpu":0,"event":"bus","rw":"r",' ..
                '"address":%d,"data":%d,"lanes":1,"device":4,"pc":%d}\n',
                frame, offset, data & 0xff, cpu.state["PC"].value))
            events:flush()
        end
    end)

_G.s32_sonic_track_write = mem:install_write_tap(
    0xc00040, 0xc00047, "s32_sonic_track_write", function(offset, data, mask)
        if frame >= track_at - 5 and frame <= track_at + track_len + 5 then
            events:write(string.format(
                '{"frame":%d,"cpu":0,"event":"bus","rw":"w",' ..
                '"address":%d,"data":%d,"lanes":1,"device":4,"pc":%d}\n',
                frame, offset, data & 0xff, cpu.state["PC"].value))
            events:flush()
        end
    end)

if mixer_trace then
    _G.s32_sonic_mixer_write = mem:install_write_tap(
        0x610000, 0x61004f, "s32_sonic_mixer_write", function(offset, data, mask)
            mixer_trace:write(string.format(
                '{"frame":%d,"pc":%d,"address":%d,"data":%d,"mask":%d}\n',
                frame, cpu.state["PC"].value, offset, data, mask))
            mixer_trace:flush()
        end)
end

if vram_trace then
    _G.s32_sonic_vram_write = mem:install_write_tap(
        0x300000, 0x300fff, "s32_sonic_vram_write", function(offset, data, mask)
            if frame >= vram_trace_first and frame <= vram_trace_last then
                vram_trace:write(string.format(
                    '{"frame":%d,"pc":%d,"address":%d,"data":%d,"mask":%d,' ..
                    '"r0":%d,"r1":%d,"r10":%d,"r11":%d}\n',
                    frame, cpu.state["PC"].value, offset, data, mask,
                    cpu.state["R0"].value, cpu.state["R1"].value,
                    cpu.state["R10"].value, cpu.state["R11"].value))
                vram_trace:flush()
            end
        end)
end

local function write_raw_ppm(token)
    local pixels, width, height = screen:pixels()
    assert(#pixels == width * height * 4)
    local temporary = string.format("%s/frame_%06d.ppm.tmp", output_dir, token)
    local final = string.format("%s/frame_%06d.ppm", output_dir, token)
    local file = assert(io.open(temporary, "wb"))
    file:write(string.format("P6\n%d %d\n255\n", width, height))
    local source = 1
    local row = {}
    for _y = 1, height do
        for x = 1, width do
            local blue, green, red = string.byte(pixels, source, source + 2)
            row[x] = string.char(red, green, blue)
            source = source + 4
        end
        file:write(table.concat(row))
    end
    file:close()
    assert(os.rename(temporary, final))
    return width, height
end

local function dump_video_state(token)
    local workram_path = string.format("%s/workram_%06d.hex", output_dir, token)
    local vram_path = string.format("%s/vram_%06d.hex", output_dir, token)
    local palette_path = string.format("%s/palette_%06d.hex", output_dir, token)
    local mixer_path = string.format("%s/mixer_%06d.hex", output_dir, token)
    local registers_path = string.format("%s/video_regs_%06d.json", output_dir, token)
    local workram = assert(io.open(workram_path, "w"))
    for word = 0, 0x7fff do
        workram:write(string.format("%04x\n", mem:read_u16(0x200000 + word * 2)))
    end
    workram:close()
    local vram = assert(io.open(vram_path, "w"))
    for word = 0, 0xffff do
        vram:write(string.format("%04x\n", mem:read_u16(0x300000 + word * 2)))
    end
    vram:close()
    local palette = assert(io.open(palette_path, "w"))
    for word = 0, 0x3fff do
        palette:write(string.format("%04x\n", mem:read_u16(0x600000 + word * 2)))
    end
    palette:close()
    local mixer = assert(io.open(mixer_path, "w"))
    for word = 0, 0x3f do
        mixer:write(string.format("%04x\n", mem:read_u16(0x610000 + word * 2)))
    end
    mixer:close()
    local registers = assert(io.open(registers_path, "w"))
    registers:write(string.format(
        '{"frame":%d,"pc":%d,"r1ff00":%d,"r1ff02":%d,' ..
        '"r1ff04":%d,"r1ff06":%d,"r1ff5c":%d,"r1ff5e":%d,' ..
        '"r1ff88":%d,"r1ff8a":%d,"r1ff8c":%d,"r1ff8e":%d}\n',
        token, cpu.state["PC"].value,
        mem:read_u16(0x31ff00), mem:read_u16(0x31ff02),
        mem:read_u16(0x31ff04), mem:read_u16(0x31ff06),
        mem:read_u16(0x31ff5c), mem:read_u16(0x31ff5e),
        mem:read_u16(0x31ff88), mem:read_u16(0x31ff8a),
        mem:read_u16(0x31ff8c), mem:read_u16(0x31ff8e)))
    registers:close()
end

_G.s32_sonic_gameplay_raw = emu.add_machine_frame_notifier(function()
    frame = frame + 1
    local coin_active = frame >= coin_at and frame < coin_at + coin_len
    local start_active = frame >= start_at and frame < start_at + start_len
    local periodic_action = action_at >= 0 and frame >= action_at and
        frame < action_end and ((frame - action_at) % action_period) < action_len
    local button_active = (frame >= button_at and frame < button_at + button_len) or
        periodic_action
    coin:set_value(coin_active and 1 or 0)
    start:set_value(start_active and 1 or 0)
    button1:set_value(button_active and 1 or 0)
    local track_step = math.max(0, math.min(frame - track_at + 1, track_len))
    track_x:set_value((track_step * track_dx) & 0xfff)
    track_y:set_value((track_step * track_dy) & 0xfff)

    if captures[frame] then
        local width, height = write_raw_ppm(frame)
        state:write(string.format(
            '{"frame":%d,"width":%d,"height":%d,"pc":%d,' ..
            '"input":{"coin":%s,"start":%s,"button1":%s,' ..
            '"track_x":%d,"track_y":%d},' ..
            '"level_clear":%d,' ..
            '"level":%d,"status0":%d,"status1":%d,"spr0":%d,"vram":%d}\n',
            frame, width, height, cpu.state["PC"].value,
            tostring(coin_active), tostring(start_active),
            tostring(button_active),
            (track_step * track_dx) & 0xfff, (track_step * track_dy) & 0xfff,
            mem:read_u16(0x20e5c4), mem:read_u16(0x20f06e),
            mem:read_u16(0x20f0bc), mem:read_u16(0x20f0be),
            mem:read_u16(0x204000), mem:read_u16(0x203f40)))
        state:flush()
    end
    if frame == dump_state_at then
        dump_video_state(frame)
    end
    if frame >= final_frame then
        machine:exit()
    end
end)

emu.add_machine_stop_notifier(function()
    if state then
        state:close()
        state = nil
    end
    if events then
        events:close()
        events = nil
    end
    if mixer_trace then
        mixer_trace:close()
        mixer_trace = nil
    end
    if vram_trace then
        vram_trace:close()
        vram_trace = nil
    end
end)
