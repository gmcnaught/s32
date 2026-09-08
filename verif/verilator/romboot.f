# Full-core romboot source manifest.  Paths are relative to the repository root.
#
# This was an uncommitted scratch file that four runners required and none
# produced, so a fresh checkout could not build the full-core sim at all.  It
# is the shipping source list with three substitutions the bench needs:
#
#   * Arcade-SegaSystem32.sv is omitted -- tb_core_romboot instantiates
#     s32_core directly as `core`, so the MiSTer top and its PLL are not used.
#   * rtl/audio/T80/ is omitted.  It is VHDL, which Verilator cannot read;
#     `SIMULATION` auto-defines S32_Z80_STUB (s32_soundsys.sv:87) and the Z80
#     is tied inactive at s32_soundsys.sv:117-119.
#   * verif/common/jt12_stub.v replaces rtl/audio/jt12/.
#
# Note rtl/prot/s32_prot.sv: it is NOT in files.qip.  The shipping source list
# is files.qip PLUS the QSF's own two entries (that file and
# rtl/cpu/v25/v25.qip), and reading files.qip alone understates it.
#
# The real-V25 profile (ga2, arabfgt) adds -f verif/v25/s80x86.f and the two
# rtl/cpu/v25/s32_v25_*.sv on the command line; see run_romboot_real_v25.sh.
rtl/s32_pkg.sv
rtl/s32_core.sv
rtl/s32_debug_hud.sv
rtl/prot/s32_prot.sv
rtl/cpu/v60/s32_v60.sv
rtl/cpu/v60/s32_v60_bus.sv
rtl/cpu/v60/s32_v60_timebase.sv
rtl/video/s32_big_dpram.sv
rtl/video/s32_vram.sv
rtl/video/s32_tilemap.sv
rtl/video/s32_sprite.sv
rtl/video/s32_linebuf.sv
rtl/video/s32_mixer.sv
rtl/video/s32_palette.sv
rtl/video/s32_video.sv
rtl/video/s32_lightgun_overlay.sv
rtl/crt_adjust.sv
rtl/audio/s32_audio_mix.sv
rtl/audio/s32_soundsys.sv
rtl/audio/s32_audio_ce.sv
rtl/audio/s32_rf5c68.sv
rtl/audio/s32_multipcm.sv
verif/common/jt12_stub.v
rtl/io/s32_io.sv
rtl/io/s32_driving_controls.sv
rtl/io/s32_lightgun.sv
rtl/io/s32_jpark_gun_gain.sv
rtl/io/s32_guncon_snac.sv
rtl/mem/sdram.sv
rtl/mem/s32_sdram_write_mux2.sv
rtl/mem/s32_rom_loader.sv
rtl/mem/s32_fb_if.sv
verif/common/s32_sdr_chip_model.sv
verif/common/s32_fb_ddr_model.sv
verif/common/s32_wave_ram_model.sv
verif/common/tb_core_romboot.sv
