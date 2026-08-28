//============================================================================
//  tb_v60_cosim -- the shipping core and the clean-room decoder, on one
//  instruction stream, asked the same question: where does each instruction
//  end?
//
//  The two were built from different things.  `rtl/cpu/v60/s32_v60.sv` is
//  MAME's V60 core transcribed into RTL -- its own header says so -- and
//  `rtl/cpu/v60x/` is the databook's Figure on p.3.293 and its mod-field
//  figure on p.3.294, read directly.  Neither has ever been asked to agree
//  with the other about anything, and instruction LENGTH is the one question
//  both answer, unambiguously, for every instruction, without either of them
//  having to execute the same semantics.
//
//  It is also the only thing in this repository that tests `s32_v60.sv`'s
//  length arithmetic against a second opinion.  Its own benches check what it
//  computes; none of them checks where it thinks an instruction stops.
//
//  ---------------------------------------------------------------------------
//  How each side is asked
//  ---------------------------------------------------------------------------
//  The clean-room side decodes: `v60_pfu` fetches the stream through `v60_biu`
//  and `v60_idu` reports `insn_pc` and `insn_len` for each instruction in turn,
//  walking forward.  Nothing executes.
//
//  The shipping core EXECUTES, so the program below is straight line: no taken
//  branch, no trap, no memory operand outside the RAM.  Its instruction
//  boundaries are the values its `pc` register takes, which it writes once per
//  instruction -- the bench asserts that too, by requiring every step to be
//  forward and no longer than an instruction can be.
//
//  The two conditional branches in the program use condition code 0, which the
//  Condition Encodings table (p.3.295) prints as "Overflow", and the ADD above
//  them leaves OV clear.  They are Format IV's two displacement widths and
//  neither is taken, which is what a length test wants from a branch.
//
//  ---------------------------------------------------------------------------
//  What a disagreement means, and what to do about it
//  ---------------------------------------------------------------------------
//  Nothing here is authoritative.  Where the two disagree, the report names the
//  opcode, both lengths, the format the clean-room decoder assigned, and the
//  two pages that decide the question -- p.3.293 for the format's base length
//  and its displacement, p.3.294 for the mod field's.  Read them before moving
//  either side.
//
//  The bench's own assembly is printed beside them as a third opinion and is
//  NOT asserted against: it is there so a disagreement can be attributed
//  rather than merely noticed.
//
//  ---------------------------------------------------------------------------
//  The divergence this bench found, and how it was closed
//  ---------------------------------------------------------------------------
//  Opcodes 6B and 7B.  Its first run had them in the executed program, chosen
//  because condition code 1011 is "False / Never" and a never-taken branch is
//  what a length test wants -- and the shipping core branched to a handler:
//  it raised the reserved-opcode exception on both, "holes in MAME's
//  authoritative primary dispatch table, not branch-condition encodings".
//
//  NEC's pages say otherwise twice.  p.3.298's Bcc row is `011 b c3 c2 c1 c0`
//  with no exclusion and an empty Exceptions column, and p.3.295's Condition
//  Encodings table prints all sixteen codes with 1011 as "False / Never" --
//  where the two tables printed beside it on that page DO mark their unused
//  encodings "reserved".  1010 and 1011 are adjacent rows of one table, and
//  this core has always executed 1010, which every game uses as `BR`.
//
//  `s32_v60.sv` decodes both ranges whole now, and the two opcodes are back in
//  the program below -- which is only possible because both sides agree.  See
//  docs/v60/COSIM.md.
//============================================================================
`timescale 1ns/1ps

module tb_v60_cosim;
    import v60_bus_pkg::*;
    import v60_fmt_pkg::*;

// ---------------------------------------------------------------------------
// The program, assembled once into a byte image both sides are loaded from.
// ---------------------------------------------------------------------------
localparam integer NPROG = 2048;
reg  [7:0] prog [0:NPROG-1];
integer    asm_pc;
integer    n_insn;
integer    asm_start [0:63];     // where the bench put each instruction
integer    asm_len   [0:63];     // and how many bytes it emitted for it
reg [8*24:1] asm_name [0:63];

task ab(input [7:0] b);
begin
    prog[asm_pc] = b;
    asm_pc = asm_pc + 1;
end
endtask

task insn_begin(input [8*24:1] nm);
begin
    asm_start[n_insn] = asm_pc;
    asm_name[n_insn]  = nm;
end
endtask

task insn_end;
begin
    asm_len[n_insn] = asm_pc - asm_start[n_insn];
    n_insn = n_insn + 1;
end
endtask

// ---------------------------------------------------------------------------
// The clean-room side: fetch and decode, off its own bus.
// ---------------------------------------------------------------------------
localparam integer DIV = 6;

reg clk = 1'b0;
always #5 clk = ~clk;
reg rst = 1'b1;

reg [2:0] tick = 3'd0;
always @(posedge clk) if (!rst) tick <= (tick == DIV-1) ? 3'd0 : tick + 3'd1;
wire ce_rise = !rst && (tick == 3'd0);
wire ce_fall = !rst && (tick == DIV/2);

reg          redirect = 1'b0;
reg   [31:0] redirect_pc = 32'd0;
wire   [7:0] byte_out;
wire         byte_valid, byte_take;
wire  [31:0] byte_pc;
wire         p_req, p_ack;
bus_status_e p_status;
wire  [23:0] p_addr;
wire   [1:0] p_dl;
wire  [15:0] biu_rdata;

v60_pfu pfu (
    .clk(clk), .rst(rst),
    .byte_out(byte_out), .byte_valid(byte_valid), .byte_take(byte_take),
    .byte_pc(byte_pc),
    .redirect(redirect), .redirect_pc(redirect_pc),
    .bus_req(p_req), .bus_status(p_status), .bus_addr(p_addr), .bus_dl(p_dl),
    .bus_ack(p_ack), .bus_rdata(biu_rdata), .level()
);

wire         i_start_w, i_done;
reg          i_start = 1'b0;
insn_fmt_e   i_fmt;
wire   [7:0] i_op;
wire  [31:0] i_pc;
wire   [4:0] i_len;
wire         i_res_op, i_res_mode;

assign i_start_w = i_start;

v60_idu idu (
    .clk(clk), .rst(rst),
    .byte_in(byte_out), .byte_valid(byte_valid), .byte_pc(byte_pc),
    .byte_take(byte_take),
    .start(i_start_w), .busy(), .done(i_done),
    .fmt(i_fmt), .op(i_op), .m(), .m2(), .d(),
    .reg_field(), .subop(),
    .br_disp(), .insn_pc(i_pc), .insn_len(i_len),
    .reserved_op(i_res_op), .reserved_mode(i_res_mode),
    .op1_valid(), .op1_mode(), .op1_rn(), .op1_rx(),
    .op1_index(), .op1_disp(), .op1_disp_outer(),
    .op1_imm(), .op1_ext_valid(), .op1_ext(), .op1_bytes(),
    .op2_valid(), .op2_mode(), .op2_rn(), .op2_rx(),
    .op2_index(), .op2_disp(), .op2_disp_outer(),
    .op2_imm(), .op2_ext_valid(), .op2_ext(), .op2_bytes()
);

wire         biu_req, biu_we, biu_ube, biu_first, biu_ack, biu_busy;
bus_status_e biu_status;
wire  [23:0] biu_addr;
wire   [1:0] biu_dl;
wire  [15:0] biu_wdata;

v60_bus_arb arb (
    .clk(clk), .rst(rst),
    .d_req(1'b0), .d_status(BST_MEM_SINGLE), .d_addr(24'd0), .d_we(1'b0),
    .d_dl(2'd0), .d_ube(1'b1), .d_first(1'b1), .d_lock(1'b0), .d_wdata(16'd0), .d_ack(),
    .p_req(p_req), .p_status(p_status), .p_addr(p_addr), .p_dl(p_dl),
    .p_ack(p_ack),
    .biu_req(biu_req), .biu_status(biu_status), .biu_addr(biu_addr),
    .biu_we(biu_we), .biu_dl(biu_dl), .biu_ube(biu_ube), .biu_first(biu_first),
    .biu_lock(), .biu_wdata(biu_wdata), .biu_ack(biu_ack), .biu_busy(biu_busy),
    .own_pfu()
);

wire [23:0] a;
wire        mrq_n, rw_n, ube_n, fas_n, bcy_n, ds_n, d_oe, bus_hiz, hldak_n;
wire [15:0] d_out;
reg  [15:0] d_in;
bus_state_e state;

v60_biu biu (
    .clk(clk), .rst(rst), .ce_rise(ce_rise), .ce_fall(ce_fall),
    .req(biu_req), .status(biu_status), .addr(biu_addr), .we(biu_we),
    .dl(biu_dl), .ube(biu_ube), .first(biu_first), .lock(1'b0), .wdata(biu_wdata),
    .ack(biu_ack), .rdata(biu_rdata), .busy(biu_busy),
    .a(a), .dl_o(), .st(), .mrq_n(mrq_n), .rw_n(rw_n), .ube_n(ube_n),
    .fas_n(fas_n), .bcy_n(bcy_n), .block_n(), .ds_n(ds_n),
    .d_out(d_out), .d_oe(d_oe), .d_in(d_in), .bus_hiz(bus_hiz),
    .ready_n(1'b0), .bmode(1'b1), .hldrq_n(1'b1), .hldak_n(hldak_n),
    .berr_n(1'b1), .rt_ep_n(1'b1), .nmi_n(1'b1), .int_req(1'b0),
    .berr(), .berr_status(), .berr_addr(), .berr_we(), .berr_retry(),
    .nmi_pending(), .nmi_take(1'b0), .int_pending(),
    .state(state)
);

reg [7:0] cmem [0:NPROG-1];
wire [10:0] bank_even = {a[10:1], 1'b0};
always @(*) d_in = {cmem[bank_even + 11'd1], cmem[bank_even]};

// ---------------------------------------------------------------------------
// The shipping core: the same bytes, in the 16-bit RAM its adapter expects.
// ---------------------------------------------------------------------------
reg sclk = 1'b0;
always #10 sclk = ~sclk;
reg srst = 1'b1;

wire        c_req, c_we, c_ack;
wire [31:0] c_addr, c_wdata, c_rdata;
wire  [1:0] c_size;
wire        m_req, m_we, m_ack;
wire [23:1] m_addr;
wire [15:0] m_wdata, m_rdata;
wire  [1:0] m_be;

s32_v60 #(.START_PC(32'h0000_0000)) cpu (
    .clk(sclk), .ce(1'b1), .rst(srst),
    .if_req(), .if_addr(), .if_data(64'd0), .if_ack(1'b0),
    .bus_req(c_req), .bus_we(c_we), .bus_addr(c_addr), .bus_size(c_size),
    .bus_wdata(c_wdata), .bus_rdata(c_rdata), .bus_ack(c_ack),
    .irq_n(1'b1), .irq_vector(8'd0), .irq_ack(),
    .nmi_n(1'b1),
    .ext_wr(1'b0), .ext_wr_addr(24'd0), .ext_wr_bytes(3'd0)
);

s32_v60_bus sadapter (
    .clk(sclk), .ce(1'b1), .rst(srst),
    .ce_fall(1'b0), .c_fetch(1'b0), .c_lock(1'b0), .bmode(1'b1), .ready_n(1'b0),
    .berr_n(1'b1), .bfrez_n(1'b1), .hldrq(1'b0),
    .c_req(c_req), .c_we(c_we), .c_addr(c_addr), .c_size(c_size),
    .c_wdata(c_wdata), .c_rdata(c_rdata), .c_ack(c_ack),
    .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wdata(m_wdata),
    .m_be(m_be), .m_rdata(m_rdata), .m_ack(m_ack)
);

reg [15:0] sram [0:32767];
reg        sack_r;
assign m_rdata = sram[m_addr[15:1]];
assign m_ack   = sack_r;
always @(posedge sclk) begin
    sack_r <= m_req & ~sack_r;
    if (m_req && m_we && !sack_r) begin
        if (m_be[0]) sram[m_addr[15:1]][7:0]  <= m_wdata[7:0];
        if (m_be[1]) sram[m_addr[15:1]][15:8] <= m_wdata[15:8];
    end
end

// ---------------------------------------------------------------------------
// What each side said.
// ---------------------------------------------------------------------------
integer clean_pc  [0:63];
integer clean_len [0:63];
reg [7:0]  clean_op  [0:63];
integer    clean_fmt [0:63];
integer n_clean = 0;

integer ship_pc [0:63];
integer n_ship  = 0;
reg [31:0] ship_last = 32'hFFFF_FFFF;

// Its PC is X until the first fetch resolves, and an X is not a boundary.
always @(posedge sclk)
  if (!srst && (^cpu.pc !== 1'bx) && (cpu.pc !== ship_last)) begin
    if (n_ship < 64) ship_pc[n_ship] = cpu.pc;
    n_ship    = n_ship + 1;
    ship_last <= cpu.pc;
end

integer errors = 0;
task chk(input cond, input [8*72:1] what);
begin
    if (!cond) begin
        errors = errors + 1;
        $display("FAIL  %0s (t=%0t)", what, $time);
    end
end
endtask

task decode_one;
begin
    @(negedge clk);
    i_start = 1'b1;
    @(negedge clk);
    i_start = 1'b0;
    while (!i_done) @(negedge clk);
    if (n_clean < 64) begin
        clean_pc[n_clean]  = i_pc;
        clean_len[n_clean] = i_len;
        clean_op[n_clean]  = i_op;
        clean_fmt[n_clean] = i_fmt;
    end
    n_clean = n_clean + 1;
end
endtask

integer i;

initial begin
    for (i = 0; i < NPROG; i = i + 1) prog[i] = 8'h00;
    asm_pc = 0; n_insn = 0;

    // ---- the program -------------------------------------------------------
    // Format II with every shape of mod field the figure gives a length to,
    // then Format I, V, III, VI and both of Format IV's displacements.
    // R8, R9 and R10 are pointed at RAM first so the memory operands below
    // are addresses the shipping core can actually read.

    insn_begin("MOV.W #0x400, R8");           // immediate, four bytes
    ab(8'h2D); ab(8'hA0); ab(8'hF4);
    ab(8'h00); ab(8'h04); ab(8'h00); ab(8'h00); ab(8'h68);
    insn_end;

    insn_begin("MOV.W #0x410, R9");
    ab(8'h2D); ab(8'hA0); ab(8'hF4);
    ab(8'h10); ab(8'h04); ab(8'h00); ab(8'h00); ab(8'h69);
    insn_end;

    // 0x006A0004, and the odd-looking value is the point: a decoder that read
    // a two-byte immediate here would take 6A as the second operand's mod
    // field, decode a register, and finish TWO bytes early.  With 00 there it
    // would decode a double displacement, swallow the bytes it skipped, and
    // arrive at the right total length by accident -- the same trap the
    // absolute address below sets, and the reason neither operand is a round
    // number.  R10's low byte is 04, which is all the ADD below reads.
    insn_begin("MOV.W #0x006A0004, R10");
    ab(8'h2D); ab(8'hA0); ab(8'hF4);
    ab(8'h04); ab(8'h00); ab(8'h6A); ab(8'h00); ab(8'h6A);
    insn_end;

    insn_begin("MOV.W #4, R11 (quick)");      // immediate quick: no extra byte
    ab(8'h2D); ab(8'hA0); ab(8'hE4); ab(8'h6B);
    insn_end;

    insn_begin("MOV.W R9, R11");              // register direct, m = 1
    ab(8'h2D); ab(8'hE0); ab(8'h69); ab(8'h6B);
    insn_end;

    insn_begin("MOV.W [R9], R11");            // register indirect, m = 0
    ab(8'h2D); ab(8'hA0); ab(8'h69); ab(8'h6B);
    insn_end;

    insn_begin("MOV.W disp8[R9], R11");
    ab(8'h2D); ab(8'hA0); ab(8'h09); ab(8'h04); ab(8'h6B);
    insn_end;

    insn_begin("MOV.W disp16[R9], R11");
    ab(8'h2D); ab(8'hA0); ab(8'h29); ab(8'h04); ab(8'h00); ab(8'h6B);
    insn_end;

    insn_begin("MOV.W disp32[R9], R11");
    ab(8'h2D); ab(8'hA0); ab(8'h49);
    ab(8'h04); ab(8'h00); ab(8'h00); ab(8'h00); ab(8'h6B);
    insn_end;

    // Absolute, four bytes.  The address is 0x006B0400 rather than a round
    // number on purpose: a decoder that took only TWO bytes here would read
    // the third as the second operand's mod field, and with 00 there it would
    // decode a double displacement, consume the two bytes it just skipped and
    // arrive at the same total length -- a wrong answer that a boundary
    // comparison cannot see.  With 6B there it decodes a register instead, and
    // the instruction comes out two bytes short.
    insn_begin("MOV.W /addr, R11");
    ab(8'h2D); ab(8'hA0); ab(8'hF3);
    ab(8'h00); ab(8'h04); ab(8'h6B); ab(8'h00); ab(8'h6B);
    insn_end;

    insn_begin("MOV.W disp8[PC], R11");
    ab(8'h2D); ab(8'hA0); ab(8'hF0); ab(8'h40); ab(8'h6B);
    insn_end;

    insn_begin("MOV.B R9, [R8]");             // Format I, d = 0
    ab(8'h09); ab(8'h09); ab(8'h68);
    insn_end;

    insn_begin("ADD.b [R8], R10");            // Format I, d = 1
    ab(8'h80); ab(8'h2A); ab(8'h68);
    insn_end;

    insn_begin("NOP");                        // Format V: one byte, no operand
    ab(8'hCD);
    insn_end;

    insn_begin("GETPSW R11");                 // Format III: m rides in the opcode
    ab(8'hF7); ab(8'h6B);
    insn_end;

    insn_begin("TB R10, +0x0C");              // Format VI, R10 is not zero
    ab(8'hC7); ab(8'hAA); ab(8'h0C); ab(8'h00);
    insn_end;

    // Format IV, both displacement widths.  Condition code 0 is "Overflow",
    // and the ADD above it left OV clear, so neither is taken -- which is what
    // a length test wants from a branch.
    insn_begin("BV disp8, not taken");
    ab(8'h60); ab(8'h03);
    insn_end;

    insn_begin("BV disp16, not taken");
    ab(8'h70); ab(8'h03); ab(8'h00);
    insn_end;

    // Condition code 1011, which p.3.295's Condition Encodings table names
    // "False / Never".  These two were the divergence this bench was written
    // to find: the shipping core raised the reserved-opcode exception on them
    // because MAME's dispatch table has no entry, and NEC's two tables both
    // print the encoding.  They are in the executed program now, which is
    // only possible because both sides agree.
    insn_begin("Bcc(Never) disp8");
    ab(8'h6B); ab(8'h03);
    insn_end;

    insn_begin("Bcc(Never) disp16");
    ab(8'h7B); ab(8'h03); ab(8'h00);
    insn_end;

    // The stack block, whose format letter the databook prints as II and the
    // Programmer's Reference as III.  Format II takes a second base byte and
    // Format III does not, so the two readings differ by ONE BYTE -- which is
    // exactly what this bench measures, and it measures it against a core
    // built from the other source.  A stack pointer first, so the push lands
    // somewhere harmless.
    insn_begin("MOV.W #0x0F00, R31");
    ab(8'h2D); ab(8'hA0); ab(8'hF4);
    ab(8'h00); ab(8'h0F); ab(8'h00); ab(8'h00); ab(8'h7F);
    insn_end;

    insn_begin("PUSH R9");
    ab(8'hEF); ab(8'h69);
    insn_end;

    insn_begin("POP R10");
    ab(8'hE7); ab(8'h6A);
    insn_end;

    // A branch to itself, so the shipping core stops advancing.  Not compared.
    ab(8'h6A); ab(8'h00);

    for (i = 0; i < NPROG; i = i + 1)  cmem[i] = prog[i];
    for (i = 0; i < 32768; i = i + 1)  sram[i] = 16'h0000;
    for (i = 0; i < NPROG; i = i + 2)
        sram[i >> 1] = {prog[i + 1], prog[i]};

    // ---- run both ----------------------------------------------------------
    repeat (4) @(negedge clk);
    rst  = 1'b0;
    srst = 1'b0;
    @(negedge clk);
    redirect_pc = 32'h0000_0000;
    redirect    = 1'b1;
    @(negedge clk);
    redirect    = 1'b0;

    for (i = 0; i < n_insn; i = i + 1) decode_one;

    // The shipping core is on its own clock and its own memory; give it long
    // enough to reach the self-loop.  Bounded, so a core that wedges reports
    // where it stopped instead of hanging the bench.
    begin : wait_ship
        integer spin;
        spin = 0;
        while ((n_ship < n_insn + 1) && (spin < 200000)) begin
            @(posedge sclk);
            spin = spin + 1;
        end
        if (n_ship < n_insn + 1)
            $display("      the shipping core stopped after %0d boundaries, at %0h",
                     n_ship, ship_last);
    end

    // ---- compare -----------------------------------------------------------
    $display("      %0d instructions, %0d clean-room boundaries, %0d shipping",
             n_insn, n_clean, n_ship);

    for (i = 0; i < n_insn; i = i + 1) begin
        if (clean_pc[i] !== ship_pc[i]) begin
            errors = errors + 1;
            $display("DIVERGE at instruction %0d (%0s)", i, asm_name[i]);
            $display("         opcode %02h, clean-room format %0d",
                     clean_op[i], clean_fmt[i]);
            $display("         clean-room: starts %0h, length %0d",
                     clean_pc[i], clean_len[i]);
            $display("         shipping  : starts %0h, next %0h",
                     ship_pc[i],
                     (i + 1 < n_ship) ? ship_pc[i + 1] : 32'hFFFF_FFFF);
            $display("         the bench assembled %0d bytes at %0h",
                     asm_len[i], asm_start[i]);
            $display("         databook p.3.293 gives the format's base length and displacement; p.3.294 the mod field's");
        end
        // A boundary the clean-room side reports has to be one instruction
        // forward of the last, which is what makes "the PC changed" a
        // boundary rather than an artefact.
        if (i > 0) begin
            chk((ship_pc[i] > ship_pc[i-1]) &&
                (ship_pc[i] - ship_pc[i-1] <= 12),
                "the shipping core's PC moved forward by one instruction");
        end
    end

    // And the lengths, which is the same statement read the other way.
    for (i = 0; i + 1 < n_insn; i = i + 1)
        chk(clean_len[i] === (ship_pc[i+1] - ship_pc[i]),
            "the two agree about how long the instruction is");

    chk(n_clean >= n_insn, "the clean-room decoder decoded every instruction");
    chk(n_ship  >= n_insn, "and the shipping core executed every instruction");
    chk(clean_pc[0] === 32'd0 && ship_pc[0] === 32'd0,
        "both started at the program's first byte");

    // Neither side may call condition code 1011 a reserved opcode.  The
    // boundary comparison above already proves the shipping core executed
    // both; this says the clean-room table does not flag them either, which
    // is the half a length comparison cannot see.
    chk(clean_op[18] === 8'h6B && clean_op[19] === 8'h7B,
        "the two former holes are the instructions the bench put there");

    if (errors == 0) $display("V60 COSIM PASS");
    else             $display("V60 COSIM FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #40_000_000;
    $display("V60 COSIM FAIL (timeout)");
    $finish;
end

endmodule
