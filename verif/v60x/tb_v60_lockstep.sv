//============================================================================
//  tb_v60_lockstep -- the shipping core and the clean-room core on one
//  program, compared where each instruction ends.
//
//  Two cores, two private copies of one memory image, one question asked
//  after every instruction: do the general registers, the four integer flags
//  and the PC agree?  Neither core is the oracle.  A disagreement is printed
//  with the opcode that retired and the field that differs, and the pages
//  decide which side is right -- verif/v60x/lockstep_known.txt records the
//  ones that have been adjudicated and the page for each.
//
//  Boundaries.  The shipping core has no retire pulse; its instruction
//  boundary is the cycle it enters S_DECODE, and the register file is settled
//  by then because its queued writes land in the cycle they are queued.  The
//  clean-room core pulses `retired` once per instruction, with `pc` already
//  the next instruction's.  So the shipping core's j-th entry into S_DECODE
//  (j >= 1; the zeroth is before any instruction) is compared with the
//  clean-room core's j-th retirement.  The two run at different rates and
//  are compared through snapshot arrays, not in real time.
//
//  Attribution.  The instruction that produced snapshot j is the one at
//  snapshot j-1's PC; its opcode byte is read from the program image, which
//  the generator never writes to.
//
//  What is not compared: R31 (the two cores are not given the same stack
//  pointer, and nothing here uses the stack) and PSW bits above the flags
//  (nothing here changes them).  Memory is compared at the end, over the
//  result slots the generator stored to and the data area it used.
//============================================================================
`timescale 1ns/1ps
module tb_v60_lockstep;
    import v60_bus_pkg::*;

localparam integer MAXK = 8192;
localparam logic [6:0] SHIPDECODE = 7'd3;   // == s32_v60 st_t S_DECODE (tb_core_romboot)

reg clk = 1'b0;
always #5 clk = ~clk;
reg rst = 1'b1;

// ---- side A: the shipping core, as tb_v60_diff.sv wires it -------------------
wire        c_req, c_we, c_ack;
wire [31:0] c_addr, c_wdata, c_rdata;
wire [1:0]  c_size;
wire        m_req, m_we, m_ack;
wire [23:1] m_addr;
wire [15:0] m_wdata, m_rdata;
wire [1:0]  m_be;

s32_v60 #(.START_PC(32'h0000_0000)) cpu (
    .clk(clk), .ce(1'b1), .rst(rst),
    .if_req(), .if_addr(), .if_data(64'd0), .if_ack(1'b0),
    .bus_req(c_req), .bus_we(c_we), .bus_addr(c_addr), .bus_size(c_size),
    .bus_wdata(c_wdata), .bus_rdata(c_rdata), .bus_ack(c_ack),
    .irq_n(1'b1), .irq_vector(8'h00), .irq_ack(), .nmi_n(1'b1),
    .ext_wr(1'b0), .ext_wr_addr(24'd0), .ext_wr_bytes(3'd0)
);
s32_v60_bus adapter (
    .clk(clk), .ce(1'b1), .rst(rst),
    .ce_fall(1'b0), .c_fetch(1'b0), .c_lock(1'b0), .bmode(1'b1), .ready_n(1'b0),
    .berr_n(1'b1), .bfrez_n(1'b1), .hldrq(1'b0),
    .c_req(c_req), .c_we(c_we), .c_addr(c_addr), .c_size(c_size),
    .c_wdata(c_wdata), .c_rdata(c_rdata), .c_ack(c_ack),
    .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wdata(m_wdata),
    .m_be(m_be), .m_rdata(m_rdata), .m_ack(m_ack)
);

reg [15:0] ram_a [65536];
reg        ack_r;
assign m_rdata = ram_a[m_addr[16:1]];
assign m_ack   = ack_r;
always @(posedge clk) begin
    ack_r <= m_req & ~ack_r;
    if (m_req && m_we && !ack_r) begin
        if (m_be[0]) ram_a[m_addr[16:1]][7:0]  <= m_wdata[7:0];
        if (m_be[1]) ram_a[m_addr[16:1]][15:8] <= m_wdata[15:8];
    end
end

// ---- side B: the clean-room core, as tb_v60_top.sv wires it ------------------
localparam integer DIV = 6;
reg [2:0] tick = 3'd0;
always @(posedge clk) if (!rst) tick <= (tick == DIV-1) ? 3'd0 : tick + 3'd1;
wire ce_rise = !rst && (tick == 3'd0);
wire ce_fall = !rst && (tick == DIV/2);

wire [23:0] b_a;
wire  [1:0] b_dl;
wire  [2:0] b_st;
wire        b_mrq_n, b_rw_n, b_ube_n, b_fas_n, b_bcy_n, b_ds_n, b_block_n, b_hldak_n, b_hiz;
wire [15:0] b_dout;
wire        b_doe;
reg  [15:0] b_din;
wire [31:0] b_pc, b_psw;
wire        b_retired, b_halted, b_stopped, b_own_pfu;
wire  [1:0] b_stop_reason;
wire  [4:0] b_cycles;
bus_state_e b_state;
reg         run = 1'b0;

v60_top #(.START_PC(32'h0000_0000)) dut (
    .clk(clk), .rst(rst), .ce_rise(ce_rise), .ce_fall(ce_fall), .run(run),
    .a(b_a), .dl_o(b_dl), .st(b_st), .mrq_n(b_mrq_n), .rw_n(b_rw_n), .ube_n(b_ube_n),
    .fas_n(b_fas_n), .bcy_n(b_bcy_n), .ds_n(b_ds_n), .block_n(b_block_n),
    .hldak_n(b_hldak_n), .bus_hiz(b_hiz),
    .d_out(b_dout), .d_oe(b_doe), .d_in(b_din),
    .ready_n(1'b0), .bmode(1'b1), .hldrq_n(1'b1), .berr_n(1'b1), .rt_ep_n(1'b1),
    .nmi_n(1'b1), .int_req(1'b0),
    .pc(b_pc), .psw(b_psw), .retired(b_retired), .halted(b_halted),
    .stopped(b_stopped), .stop_reason(b_stop_reason), .insn_cycles(b_cycles),
    .state(b_state), .own_pfu(b_own_pfu),
    .pr_id(5'd0), .pr_wr(1'b0), .pr_wdata(32'd0)
);

reg   [7:0] mem_b [65536];
wire [15:0] bank_even = {b_a[15:1], 1'b0};
always_comb b_din = {mem_b[bank_even + 16'd1], mem_b[bank_even]};
wire b_ack = dut.u_biu.ack;
always @(posedge clk) if (!rst && b_ack && !b_rw_n) begin
    case ({b_ube_n, b_a[0]})
        2'b00: begin mem_b[bank_even] = b_dout[7:0];
                     mem_b[bank_even + 16'd1] = b_dout[15:8]; end
        2'b01: mem_b[bank_even + 16'd1] = b_dout[15:8];
        2'b10: mem_b[bank_even] = b_dout[7:0];
        default: ;
    endcase
end

// ---- the image ------------------------------------------------------------------
reg  [15:0] words [32768];
reg   [7:0] prog  [65536];    // the program as loaded, for opcode attribution
reg [1023:0] hexfile;
integer i, j;

// ---- snapshots --------------------------------------------------------------------
reg [31:0] a_pc   [MAXK];
reg  [3:0] a_fl   [MAXK];
reg [31:0] a_reg  [MAXK][31];
reg [31:0] b_pcs  [MAXK];
reg  [3:0] b_fl   [MAXK];
reg [31:0] b_reg  [MAXK][31];
integer a_n = 0, b_n = 0;       // snapshots taken
integer cmp_n = 0;              // snapshots compared
integer n_diverge = 0;
reg [6:0] a_st_d = 7'd0;
// A field is reported the first time it differs, not on every instruction
// until something reloads it: a diverged register stays diverged until the
// program overwrites it, and that is the island's business, not a new finding.
reg [30:0] r_open = 31'd0;
reg  [3:0] f_open = 4'd0;
reg        pc_open = 1'b0;

// side A: entering S_DECODE
always @(posedge clk) if (!rst) begin
    a_st_d <= cpu.st;
    if (cpu.st == SHIPDECODE && a_st_d != SHIPDECODE && a_n < MAXK) begin
        a_pc[a_n] = cpu.pc;
        a_fl[a_n] = cpu.psw[3:0];
        for (j = 0; j < 31; j = j + 1) a_reg[a_n][j] = cpu.r[j];
        a_n = a_n + 1;
    end
end

// side B: the retire pulse.  Snapshot 0 is the state before the first
// instruction, so that the two arrays are indexed alike.
always @(posedge clk) if (!rst && b_retired && b_n < MAXK && b_n > 0) begin
    b_pcs[b_n] = b_pc;
    b_fl[b_n]  = b_psw[3:0];
    for (j = 0; j < 31; j = j + 1) b_reg[b_n][j] = dut.u_rf.gpr[j];
    b_n = b_n + 1;
end

// ---- compare, as both sides reach k -----------------------------------------------
task automatic report(input integer k, input logic [8*8:1] field,
                      input logic [31:0] va, input logic [31:0] vb);
    reg [31:0] ipc;
    begin
        ipc = a_pc[k-1];
        $display("DIVERGE k=%0d pc=%08x op=%02x field=%0s ship=%08x clean=%08x",
                 k, ipc, prog[ipc[15:0]], field, va, vb);
        n_diverge = n_diverge + 1;
    end
endtask

always @(posedge clk) if (!rst) begin
    while (cmp_n < a_n && cmp_n < b_n) begin
        if (cmp_n > 0) begin
            if (a_pc[cmp_n] !== b_pcs[cmp_n]) begin
                if (!pc_open) report(cmp_n, "PC", a_pc[cmp_n], b_pcs[cmp_n]);
                pc_open = 1'b1;
            end else pc_open = 1'b0;
            for (j = 0; j < 4; j = j + 1)
                if (a_fl[cmp_n][j] !== b_fl[cmp_n][j]) begin
                    if (!f_open[j]) case (j)
                        3: report(cmp_n, "PSW.CY", a_fl[cmp_n], b_fl[cmp_n]);
                        2: report(cmp_n, "PSW.OV", a_fl[cmp_n], b_fl[cmp_n]);
                        1: report(cmp_n, "PSW.S",  a_fl[cmp_n], b_fl[cmp_n]);
                        default: report(cmp_n, "PSW.Z", a_fl[cmp_n], b_fl[cmp_n]);
                    endcase
                    f_open[j] = 1'b1;
                end else f_open[j] = 1'b0;
            for (j = 0; j < 31; j = j + 1)
                if (a_reg[cmp_n][j] === b_reg[cmp_n][j]) r_open[j] = 1'b0;
                else if (r_open[j]) ;
                else begin
                    r_open[j] = 1'b1;
                    case (j)
                        0: report(cmp_n, "R0", a_reg[cmp_n][j], b_reg[cmp_n][j]);
                        1: report(cmp_n, "R1", a_reg[cmp_n][j], b_reg[cmp_n][j]);
                        2: report(cmp_n, "R2", a_reg[cmp_n][j], b_reg[cmp_n][j]);
                        3: report(cmp_n, "R3", a_reg[cmp_n][j], b_reg[cmp_n][j]);
                        4: report(cmp_n, "R4", a_reg[cmp_n][j], b_reg[cmp_n][j]);
                        5: report(cmp_n, "R5", a_reg[cmp_n][j], b_reg[cmp_n][j]);
                        6: report(cmp_n, "R6", a_reg[cmp_n][j], b_reg[cmp_n][j]);
                        7: report(cmp_n, "R7", a_reg[cmp_n][j], b_reg[cmp_n][j]);
                        8: report(cmp_n, "R8", a_reg[cmp_n][j], b_reg[cmp_n][j]);
                        default: report(cmp_n, "Rn", a_reg[cmp_n][j], b_reg[cmp_n][j]);
                    endcase
                end
        end
        cmp_n = cmp_n + 1;
    end
end

// ---- run ------------------------------------------------------------------------------
integer n_mem_diverge;
initial begin
    for (i = 0; i < 65536; i = i + 1) begin ram_a[i] = 16'h0000; mem_b[i] = 8'h00; prog[i] = 8'h00; end
    for (i = 0; i < 32768; i = i + 1) words[i] = 16'h0000;
    if (!$value$plusargs("hex=%s", hexfile)) begin
        $display("no +hex=");
        $finish;
    end
    $readmemh(hexfile, words);
    for (i = 0; i < 32768; i = i + 1) begin
        ram_a[i]       = words[i];
        mem_b[2*i]     = words[i][7:0];
        mem_b[2*i + 1] = words[i][15:8];
        prog[2*i]      = words[i][7:0];
        prog[2*i + 1]  = words[i][15:8];
    end
    // MAME's device_start zeroes R0..R30 (tb_core_romboot does the same).
    for (i = 0; i < 31; i = i + 1) cpu.r[i] = 32'h0000_0000;

    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (DIV*4) @(negedge clk);
    run = 1'b1;
    b_n = 1;   // snapshot 0 is reserved; see above

    for (i = 0; i < 2000000 &&
                !((cpu.halted || a_n >= MAXK) && (b_halted || b_stopped || b_n >= MAXK));
         i = i + 1)
        @(posedge clk);
    repeat (4) @(posedge clk);

    if (b_stopped)
        $display("STOP reason=%0d pc=%08x op=%02x after %0d instructions",
                 b_stop_reason, b_pc, prog[b_pc[15:0]], b_n - 1);
    if (!cpu.halted) $display("SHIP did not halt: pc=%08x snapshots=%0d", cpu.pc, a_n);
    if (!b_halted && !b_stopped)
        $display("CLEAN did not halt: pc=%08x snapshots=%0d", b_pc, b_n - 1);

    // memory: the result slots and the data area, byte by byte
    n_mem_diverge = 0;
    for (i = 16'h8000; i < 16'h8A00; i = i + 1)
        if (ram_a[i >> 1][8*(i & 1) +: 8] !== mem_b[i]) begin
            if (n_mem_diverge < 16)
                $display("MEMDIVERGE addr=%04x ship=%02x clean=%02x", i,
                         ram_a[i >> 1][8*(i & 1) +: 8], mem_b[i]);
            n_mem_diverge = n_mem_diverge + 1;
        end

    $display("LOCKSTEP instructions=%0d compared=%0d diverge=%0d memdiverge=%0d stop=%0d",
             a_n - 1, cmp_n - 1, n_diverge, n_mem_diverge, b_stopped);
    $display("V60 LOCKSTEP DONE");
    $finish;
end

endmodule
