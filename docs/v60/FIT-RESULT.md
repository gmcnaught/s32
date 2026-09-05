# The clean-room V60's first fit

Standalone, on the DE10-Nano's device, 2026-09-05. Project:
`verif/quartus_v60x/` (`v60x_fit.qsf`, a `v60x_probe` wrapper around
`v60_top`, every port virtual except the clock). Quartus Lite 17.0.2, the
production build's optimisation settings, `clk` constrained to clk_ram's
period, 10.348 ns, with no multicycle relief at all.

`docs/v60/NEXT-STEPS.md` said any claim about replacing `rtl/cpu/v60/` starts
with a fit. This is that fit, and it answers the area question and asks the
timing one.

## Area

| | clean-room `v60_top` | for scale |
|---|---|---|
| ALMs | **7,414** of 41,910 (18 %) | the whole shipping design is 37,423 ALMs at 89 % |
| registers | 5,372 | |
| block memory | 0 bits | the register file and the privileged registers are flops |
| DSP blocks | 0 | the multiplier is shift-add (`v60_muldiv`) |

So the core as it stands would take roughly a fifth of the device. What the
shipping V60 alone costs is not recorded in this tree; `verif/quartus_v60/`
exists to measure it and has not been run under the same settings.

## Timing

| corner | Fmax on `clk` | worst setup slack |
|---|---|---|
| Slow 1100 mV 100 °C | **20.58 MHz** | **−38.2 ns** against a 10.348 ns period |

The worst path has **46 logic levels** and 48 ns of data delay. It runs from
`u_idu.op[6]` — the opcode byte the decoder holds — through the opcode table
and the ALU to `u_seq.ea_wdata[4]`, the operand write data. That is the
decode-to-result chain evaluated combinationally in one cycle: which
operation the opcode is, the ALU that performs it, and the sequencer's
selection of what to write. The ten worst paths are all instances of it.

## What that means

The sequencer, address unit and data unit advance every `clk`; only `v60_biu`
divides by six. So the core needs `clk` to close at 96.6 MHz for its internal
state machines even though the bus only moves once per V60 clock. It closes at
a fifth of that. Nothing about the *bus* is in the worst path; it is the
execution stage, which was built for correctness against the pages and never
against a clock.

Two ways forward, and they are not exclusive:

1. **Pipeline the decode.** Register the opcode table's answer (`op_alu`,
   the operand widths) when the decoder finishes, so the ALU sees a decoded
   operation rather than a byte. The sequencer already waits a cycle for the
   decoder; this is where the levels come from and where they can go.
2. **Run the execution stage on the V60 clock, not `clk`.** Gate the
   sequencer, address unit and data unit on `ce_rise` the way the BIU already
   is, and give them the multicycle exception the shipping core's ce-gated
   registers have in `s32.sdc`. That divides the requirement by six and puts
   the 20 MHz figure inside the 16.1 MHz the V60 clock actually is — with the
   margin the shipping design does not have.

Neither has been tried. The number to beat is the shipping core's, which
closes the whole design at +0.224 ns on the same domain.
