// Non-invasive probe for the four shipping deltas between rtl/cpu/v60 and the
// upstream meathax-s32 V60.  Bound into s32_v60.
// Observation-only: it drives nothing and prints once at $finish, so adding
// it to a build cannot change what the core does.
//
//   D1  ext_wr prefetch invalidation   -- upstream has no such path at all
//   D2  HALT wake                      -- upstream goes straight to S_DECODE
//   D3  IRQ vector width               -- upstream truncates irq_vector+0x40 to 8 bits
//   D4  6B/7B Bcc                      -- measured from +OPTRACE, not here
module v60_delta_probe (
    input             clk,
    input             rst,
    input             ce,
    input      [31:0] pc,
    input             halted,
    input       [8:0] exc_vector,
    input             ext_fb_inval,
    input             ext_pv_inval,
    input             ext_wr,
    input             irq_n,
    input             psw_ie,
    input       [7:0] irq_vector
);
    integer n_ext_fb = 0, n_ext_pv = 0, n_ext_wr = 0;
    integer n_halt_enter = 0, n_halt_wake = 0, n_halt_wake_irq = 0;
    integer n_irq_disp = 0, n_vec_wrap = 0;
    integer vhist [0:255];          // irq_vector value at each IRQ dispatch
    reg fb_d = 0, pv_d = 0, halt_d = 0;
    reg [8:0] exc_d = 0;
    integer i;

    initial for (i = 0; i < 256; i = i + 1) vhist[i] = 0;

    always @(posedge clk) if (!rst) begin
        // D1: external-write prefetch invalidation (rising edges only)
        if (ext_wr) n_ext_wr = n_ext_wr + 1;
        if (ext_fb_inval && !fb_d) n_ext_fb = n_ext_fb + 1;
        if (ext_pv_inval && !pv_d) n_ext_pv = n_ext_pv + 1;
        fb_d <= ext_fb_inval;
        pv_d <= ext_pv_inval;

        if (ce) begin
            // D2: HALT enter / wake
            if (halted && !halt_d) n_halt_enter = n_halt_enter + 1;
            if (!halted && halt_d) begin
                n_halt_wake = n_halt_wake + 1;
                if (!irq_n && psw_ie) n_halt_wake_irq = n_halt_wake_irq + 1;
            end
            halt_d <= halted;

            // D3: every exception dispatch, by vector.  >= 0x40 is an IRQ, and
            // upstream's 8-bit `irq_vector + 8'h40` wraps whenever the game's
            // programmed vector is >= 0xC0.
            if (exc_vector != exc_d) begin
                if (exc_vector >= 9'h40) begin
                    n_irq_disp = n_irq_disp + 1;
                    vhist[irq_vector] = vhist[irq_vector] + 1;
                    if ({1'b0, irq_vector} + 9'h40 > 9'h0ff) n_vec_wrap = n_vec_wrap + 1;
                end
            end
            exc_d <= exc_vector;
        end
    end

    final begin
        $display("PROBE D1 ext_wr_cycles=%0d fb_inval=%0d pv_inval=%0d",
                 n_ext_wr, n_ext_fb, n_ext_pv);
        $display("PROBE D2 halt_enter=%0d halt_wake=%0d halt_wake_by_irq=%0d",
                 n_halt_enter, n_halt_wake, n_halt_wake_irq);
        $display("PROBE D3 irq_dispatch=%0d would_wrap_upstream=%0d", n_irq_disp, n_vec_wrap);
        for (i = 0; i < 256; i = i + 1)
            if (vhist[i] != 0)
                $display("PROBE D3 vec=%02x n=%0d upstream_exc=%02x fork_exc=%03x",
                         i, vhist[i], (i + 8'h40) & 8'hff, i + 9'h40);
    end
endmodule

bind s32_v60 v60_delta_probe u_v60_delta_probe (
    .clk(clk), .rst(rst), .ce(ce), .pc(pc), .halted(halted),
    .exc_vector(exc_vector), .ext_fb_inval(ext_fb_inval),
    .ext_pv_inval(ext_pv_inval), .ext_wr(ext_wr),
    .irq_n(irq_n), .psw_ie(psw_ie), .irq_vector(irq_vector)
);
