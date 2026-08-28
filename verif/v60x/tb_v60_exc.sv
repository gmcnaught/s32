//============================================================================
//  tb_v60_exc -- an exception taken against real memory.
//
//  v60_exc drives v60_dxu drives v60_biu drives the two-bank memory model, so
//  the vector is fetched and the frame is pushed the way anything else on this
//  bus is: the frame's words are checked where they land, and the whole thing
//  is counted in bus cycles, which is the currency the rest of this tree uses.
//
//  The vector arithmetic has an independent check built into the page: the
//  Programmer's Reference prints BRKV's operation as "PC <- [ Exception Vector
//  21 ]", and its Figure 8-2 puts the Integer Arithmetic Exception at SBT
//  offset +84.  84 = 4 x 21, so the offset map and the instruction page
//  confirm each other, and this bench uses both.
//============================================================================
`timescale 1ns/1ps

module tb_v60_exc;
    import v60_bus_pkg::*;
    import v60_psw_pkg::*;

localparam integer DIV = 6;

reg clk = 1'b0;
always #5 clk = ~clk;

reg rst = 1'b1;

reg [2:0] tick = 3'd0;
always @(posedge clk) if (!rst) tick <= (tick == DIV-1) ? 3'd0 : tick + 3'd1;
wire ce_rise = !rst && (tick == 3'd0);
wire ce_fall = !rst && (tick == DIV/2);

// ---- the unit ---------------------------------------------------------------
reg          e_req = 1'b0, e_int = 1'b0, e_dis = 1'b0;
reg          e_ist = 1'b0, e_ackv = 1'b0;
wire   [7:0] e_int_vec;
wire         e_invalid;
reg    [7:0] e_vec = 8'd0;
reg   [31:0] e_ret = 32'd0, e_psw = 32'd0, e_sp = 32'd0, e_sbr = 32'd0;
reg    [1:0] e_np = 2'd0;
reg   [31:0] e_p0 = 32'd0, e_p1 = 32'd0;
reg   [15:0] e_code = 16'd0;

wire  [31:0] e_sp_out, e_psw_out, e_handler;
wire         e_busy, e_done;
wire   [3:0] e_cycles;

wire         dx_req, dx_we, dx_done, dx_intack;
wire  [23:0] dx_addr;
wire   [3:0] dx_nbytes, dx_cycles;
wire  [63:0] dx_wdata, dx_rdata;

v60_exc dut (
    .clk(clk), .rst(rst),
    .req(e_req), .vector(e_vec), .ret_pc(e_ret), .psw_in(e_psw),
    .sp_in(e_sp), .sbr(e_sbr),
    .nparams(e_np), .code(e_code), .param0(e_p0), .param1(e_p1),
    .is_interrupt(e_int), .disable_ie(e_dis), .int_stack(e_ist),
    .ack_vector(e_ackv),
    .sp_out(e_sp_out), .psw_out(e_psw_out), .handler_pc(e_handler),
    .busy(e_busy), .done(e_done), .bus_cycles(e_cycles),
    .int_vector(e_int_vec), .invalid_int(e_invalid),
    .dx_req(dx_req), .dx_addr(dx_addr), .dx_nbytes(dx_nbytes), .dx_we(dx_we),
    .dx_intack(dx_intack),
    .dx_wdata(dx_wdata), .dx_rdata(dx_rdata), .dx_done(dx_done),
    .dx_cycles(dx_cycles)
);

wire         biu_req, biu_we, biu_ube, biu_first, biu_ack;
bus_status_e biu_status;
wire  [23:0] biu_addr;
wire   [1:0] biu_dl;
wire  [15:0] biu_wdata, biu_rdata;

v60_dxu dxu (
    .clk(clk), .rst(rst),
    .req(dx_req), .addr(dx_addr), .nbytes(dx_nbytes), .we(dx_we), .io(1'b0), .lock(1'b0), .intack(dx_intack),
    .wdata(dx_wdata), .rdata(dx_rdata), .busy(), .done(dx_done),
    .cycles(dx_cycles),
    .biu_req(biu_req), .biu_status(biu_status), .biu_addr(biu_addr),
    .biu_we(biu_we), .biu_dl(biu_dl), .biu_ube(biu_ube), .biu_first(biu_first),
    .biu_wdata(biu_wdata), .biu_ack(biu_ack), .biu_rdata(biu_rdata)
);

wire [23:0] a;
wire  [1:0] dl_o;
wire  [2:0] st;
wire        mrq_n, rw_n, ube_n, fas_n, bcy_n, ds_n, d_oe, bus_hiz, hldak_n;
wire [15:0] d_out;
reg  [15:0] d_in;
bus_state_e state;

v60_biu biu (
    .clk(clk), .rst(rst), .ce_rise(ce_rise), .ce_fall(ce_fall),
    .req(biu_req), .status(biu_status), .addr(biu_addr), .we(biu_we),
    .dl(biu_dl), .ube(biu_ube), .first(biu_first), .lock(1'b0), .wdata(biu_wdata),
    .ack(biu_ack), .rdata(biu_rdata), .busy(),
    .a(a), .dl_o(dl_o), .st(st), .mrq_n(mrq_n), .rw_n(rw_n), .ube_n(ube_n),
    .fas_n(fas_n), .bcy_n(bcy_n), .block_n(), .ds_n(ds_n),
    .d_out(d_out), .d_oe(d_oe), .d_in(d_in), .bus_hiz(bus_hiz),
    .ready_n(1'b0), .bmode(1'b1), .hldrq_n(1'b1), .hldak_n(hldak_n),
    .berr_n(1'b1), .rt_ep_n(1'b1), .nmi_n(1'b1), .int_req(1'b0),
    .berr(), .berr_status(), .berr_addr(), .berr_we(), .berr_retry(),
    .nmi_pending(), .nmi_take(1'b0), .int_pending(),
    .state(state)
);

reg  [7:0] mem [0:8191];
wire [12:0] bank_even = {a[12:1], 1'b0};

// ---- a stand-in for the uPD71059 -------------------------------------------
// "On the SECOND interrupt acknowledge cycle, an 8-bit interrupt vector is
// read" (p.3.237).  So the model answers the two cycles of the pair
// differently, and a machine that kept the first one's byte fails rather than
// passing on a controller that happened to hold the vector across both.
wire       is_iack = ({mrq_n, st} === 4'b1110);
reg  [7:0] iack_first  = 8'hC0;
reg  [7:0] iack_second = 8'hC8;
integer    iack_n = 0;

always @(*) d_in = is_iack ? {8'h00, (iack_n == 0) ? iack_first : iack_second}
                           : {mem[bank_even + 13'd1], mem[bank_even]};

integer nack = 0, n_iack = 0;
always @(posedge clk) if (!rst && biu_ack) begin
    nack = nack + 1;
    if (is_iack) begin iack_n = iack_n + 1; n_iack = n_iack + 1; end
    if (!rw_n) begin
        case ({ube_n, a[0]})
            2'b00: begin mem[bank_even] = d_out[7:0];
                         mem[bank_even + 13'd1] = d_out[15:8]; end
            2'b01: mem[bank_even + 13'd1] = d_out[15:8];
            2'b10: mem[bank_even] = d_out[7:0];
            default: ;
        endcase
    end
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

function [31:0] word_at(input [12:0] addr);
    word_at = {mem[addr + 13'd3], mem[addr + 13'd2],
               mem[addr + 13'd1], mem[addr]};
endfunction

task put_word(input [12:0] addr, input [31:0] val);
begin
    mem[addr]        = val[7:0];
    mem[addr + 13'd1] = val[15:8];
    mem[addr + 13'd2] = val[23:16];
    mem[addr + 13'd3] = val[31:24];
end
endtask

task take;
begin
    @(negedge clk);
    iack_n = 0;
    n_iack = 0;
    e_req = 1'b1;
    @(negedge clk);
    e_req = 1'b0;
    while (!e_done) @(negedge clk);
end
endtask

integer i;

initial begin
    for (i = 0; i < 8192; i = i + 1) mem[i] = 8'h00;

    // The system base table at 0x1000, which is page aligned as the page
    // requires.  Two entries, at the offsets Figure 8-2 gives:
    //   vector 16, "+64"  Reserved Opcode Exception
    //   vector 21, "+84"  Integer Arithmetic Exception -- BRKV's vector
    put_word(13'h1000 + 13'd64, 32'h0000_2000);
    put_word(13'h1000 + 13'd84, 32'h0000_3000);
    // and one in the user range, vector 200
    put_word(13'h1000 + 13'd800, 32'h0000_4000);
    // and vector 192, which is what the FIRST acknowledge cycle would give
    put_word(13'h1000 + 13'd768, 32'h0000_5000);
    // vector 4, the System Fault the Invalid Interrupt raises -- Figure 8-2's
    // "+16 System Fault"
    put_word(13'h1000 + 13'd16,  32'h0000_6000);
    // vector 3, the Serious System Fault -- Figure 8-2's "+12"
    put_word(13'h1000 + 13'd12,  32'h0000_7000);

    repeat (4) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);

    // =======================================================================
    // A reserved opcode exception: vector 16, two parameter words.
    // =======================================================================
    e_sbr = 32'h0000_1000;
    e_sp  = 32'h0000_0800;
    e_psw = 32'h0304_0000 | (32'h1 << PSW_IE);   // EL = 3, interrupts enabled
    e_vec  = 8'd16;
    e_ret  = 32'h0000_0110;                       // the Next PC
    e_np   = 2'd1;                                // one word ABOVE the code word
    e_p0   = 32'h0000_0100;                       // the Current PC
    e_p1   = 32'hDEAD_BEEF;                       // and nothing reaches for this
    e_code = 16'h1000;                            // reserved opcode
    e_int = 1'b0; e_dis = 1'b0;
    take;

    chk(e_handler === 32'h0000_2000,
        "the handler comes from SBR + 4 x vector");
    // The frame, in the order BRKV prints it: "[-SP] <- CurrentPC ; [-SP] <-
    // Exception Code ; [-SP] <- PSW ; [-SP] <- NextPC".
    chk(word_at(13'h7FC) === 32'h0000_0100, "the parameter word is pushed first");
    chk(word_at(13'h7F8) === 32'h1000_0008,
        "then the exception code beside the parameter count, in one word");
    chk(word_at(13'h7F4) === e_psw,         "then the PSW as it was");
    chk(word_at(13'h7F0) === 32'h0000_0110, "and the return PC last, on top");
    chk(e_sp_out === 32'h0000_07F0,         "the stack pointer comes back moved");
    // 2 cycles for the vector, 2 for each of four pushed words.
    chk(e_cycles === 4'd10,
        "a four word frame and a vector read is ten bus cycles");

    // The PSW the handler runs with.
    chk(e_psw_out[PSW_EL_HI:PSW_EL_LO] === 2'b00,
        "the handler runs at execution level 0");
    chk(e_psw_out[PSW_IE] === 1'b1,
        "an exception leaves the interrupt enable alone");
    chk(e_psw_out[PSW_IS] === 1'b0,
        "and does not move to the interrupt stack");

    // =======================================================================
    // BRKV's vector, which two pages agree on: "Exception Vector 21" and the
    // Integer Arithmetic Exception at offset +84.
    // =======================================================================
    e_vec  = 8'd21;
    e_sp   = 32'h0000_0700;
    e_np   = 2'd0;
    e_code = 16'h2001;               // integer overflow
    take;
    chk(e_handler === 32'h0000_3000, "vector 21 reads the entry at +84");
    chk(word_at(13'h6FC) === 32'h2001_0004,
        "with nothing above it, the code word is pushed first");
    chk(word_at(13'h6F8) === e_psw,  "then the PSW");
    chk(word_at(13'h6F4) === 32'h0000_0110, "and the return PC on top of it");
    chk(e_sp_out === 32'h0000_06F4,  "three words of frame");
    chk(e_cycles === 4'd8,           "two cycles for the vector and six for the frame");

    // =======================================================================
    // ONE parameter word, which is what every Instruction Exception has: the
    // table's frame for vectors 16 to 20 is "+8 Exception Code / +4 PSW / PC
    // (Current PC)" with a parameter count of 4 -- four bytes, one word.  It
    // is param0, not param1: the parameters go down in order.
    // =======================================================================
    e_vec  = 8'd16;
    e_sp   = 32'h0000_0780;
    e_np   = 2'd1;
    e_p0   = 32'h0000_0100;           // the one parameter word
    e_p1   = 32'hDEAD_BEEF;           // and nothing should reach for this
    e_code = 16'h1000;                // the reserved-opcode exception code
    e_int  = 1'b0;
    take;
    chk(word_at(13'h77C) === 32'h0000_0100,
        "a single parameter word is param0, not param1");
    chk(word_at(13'h778) === 32'h1000_0008,
        "and the count beside the code counts it: two words, eight bytes");
    chk(word_at(13'h774) === e_psw,   "with the PSW under them");
    chk(word_at(13'h770) === 32'h0000_0110, "and the return PC on top");
    chk(e_sp_out === 32'h0000_0770,   "four words of frame");
    chk(e_cycles === 4'd10,           "a vector read and four words pushed");

    // =======================================================================
    // An interrupt: the enable is cleared and the interrupt stack is selected.
    // =======================================================================
    e_vec = 8'd200;                   // in the user range, 64-255
    e_sp  = 32'h0000_0600;
    e_np  = 2'd0;
    e_int = 1'b1;
    take;
    chk(e_handler === 32'h0000_4000, "a user vector reads its own entry");
    // "Interrupt Stack Format: PSW, PC" -- Figure 8-3 draws the interrupt
    // frame as those two words and nothing else, where the exception frame
    // beside it has the code word and the parameters above them.
    chk(word_at(13'h5FC) === e_psw,  "an interrupt pushes the PSW");
    chk(word_at(13'h5F8) === 32'h0000_0110, "and the return PC, and no more");
    chk(e_sp_out === 32'h0000_05F8,
        "so its frame is two words, not three: no exception code word");
    chk(e_cycles === 4'd6,           "and it costs two bus cycles less");
    chk(e_psw_out[PSW_IE] === 1'b0,
        "an interrupt disables further maskable interrupts");
    chk(e_psw_out[PSW_IS] === 1'b1,
        "and selects the interrupt stack, which is the reading this tree marks");
    chk(e_psw_out[PSW_EL_HI:PSW_EL_LO] === 2'b00,
        "at execution level 0, like everything else here");

    // An interrupt asked for parameter words anyway.  There is no such frame
    // to build -- Figure 8-3 gives the interrupt format two words -- so the
    // request is ignored rather than half honoured, and the module says so.
    e_vec = 8'd200;
    e_sp  = 32'h0000_0580;
    e_np  = 2'd2;
    e_p0  = 32'hAAAA_AAAA;
    e_p1  = 32'hBBBB_BBBB;
    take;
    chk(word_at(13'h57C) === e_psw,   "an interrupt's frame is the PSW");
    chk(word_at(13'h578) === 32'h0000_0110, "and the return PC");
    chk(e_sp_out === 32'h0000_0578,
        "and asking for parameters does not add any");
    e_np = 2'd0;

    // Note 2: a bus error or stack invalid exception disables interrupts too,
    // without being an interrupt.
    e_int = 1'b0; e_dis = 1'b1;
    e_vec = 8'd16; e_sp = 32'h0000_0500;
    take;
    chk(e_psw_out[PSW_IE] === 1'b0,
        "a bus error or stack invalid exception disables interrupts as well");
    chk(e_psw_out[PSW_IS] === 1'b0,
        "but does not move to the interrupt stack");

    // =======================================================================
    // The rest of the recognition sequence.  The databook prints it with every
    // digit legible (pp.3.269-3.270) where the Programmer's Reference's copy
    // lost three: TE <- 0, TP <- 0, AE <- 0, EM <- 0 and ASA <- 1.  Start
    // with each of them the other way round, so every one of the five has to
    // move.
    // =======================================================================
    e_int = 1'b0; e_dis = 1'b0;
    e_vec = 8'd16;
    e_sp  = 32'h0000_0400;
    e_np  = 2'd0;
    e_psw = (32'h1 << PSW_TE) | (32'h1 << PSW_TP) | (32'h1 << PSW_AE) |
            (32'h1 << PSW_EM) | (32'h1 << PSW_IE);
    take;
    chk(e_psw_out[PSW_TE]  === 1'b0, "a handler starts with tracing off");
    chk(e_psw_out[PSW_TP]  === 1'b0, "and no trace pending");
    chk(e_psw_out[PSW_AE]  === 1'b0, "and address traps off");
    chk(e_psw_out[PSW_EM]  === 1'b0, "in native mode, not emulation mode");
    chk(e_psw_out[PSW_ASA] === 1'b1,
        "with asynchronous system traps held off while it runs");
    chk(word_at(13'h3F8) === e_psw,
        "and the PSW it pushed is the one it found, not the one it built");

    // =======================================================================
    // A maskable interrupt, whose vector is not the caller's.  "If set, the
    // uPD70616 will perform a pair of back-to-back interrupt acknowledge
    // cycles.  On the second interrupt acknowledge cycle, an 8-bit interrupt
    // vector is read from the external uPD71059 Interrupt Controller and used
    // as an offset into the System Base Table" (p.3.237).
    // =======================================================================
    e_psw  = 32'h0304_0000 | (32'h1 << PSW_IE);
    e_int  = 1'b1; e_dis = 1'b0; e_ist = 1'b1; e_ackv = 1'b1;
    e_vec  = 8'd99;                   // and this is ignored outright
    e_sp   = 32'h0000_0300;
    e_np   = 2'd0;
    iack_first  = 8'hC0;              // 192: an entry that exists, and is wrong
    iack_second = 8'hC8;              // 200: the one the page puts on cycle two
    take;
    chk(n_iack == 2,
        "a maskable interrupt makes a PAIR of interrupt acknowledge cycles");
    chk(e_int_vec === 8'hC8,
        "and the vector is the byte from the SECOND of them");
    chk(e_handler === 32'h0000_4000,
        "so the handler is vector 200's entry, not vector 192's");
    chk(!e_invalid, "a vector of 200 is one of the 192 the application owns");
    chk(word_at(13'h2FC) === e_psw,          "the frame is the PSW");
    chk(word_at(13'h2F8) === 32'h0000_0110,  "and the return PC, and no more");
    chk(e_sp_out === 32'h0000_02F8,          "two words");
    // two acknowledge cycles, two for the vector, four for the frame
    chk(e_cycles === 4'd8,
        "and it costs the pair of acknowledge cycles on top of an interrupt");
    chk(e_psw_out[PSW_IE] === 1'b0,  "it disables further maskable interrupts");
    chk(e_psw_out[PSW_IS] === 1'b1,  "and runs on the interrupt stack");

    // "An invalid interrupt exception occurs when an external interrupt
    // controller supplies a system base table vector in the range of 0 to 63"
    // (§8).  It is the System Fault -- vector 4, code 0400 -- and its frame is
    // an EXCEPTION's, which Figure 8-5 draws with the code word an interrupt
    // does not have.
    e_sp        = 32'h0000_0280;
    iack_second = 8'd63;              // the top of the reserved range
    take;
    chk(e_int_vec === 8'd63,       "the controller supplied a reserved vector");
    chk(e_invalid,                 "which is the Invalid Interrupt exception");
    chk(e_handler === 32'h0000_6000,
        "so the handler is vector 4's entry, the System Fault");
    chk(word_at(13'h27C) === 32'h0400_0004,
        "and the frame gains a code word: 0400, with a parameter count of 4");
    chk(word_at(13'h278) === e_psw,         "then the PSW");
    chk(word_at(13'h274) === 32'h0000_0110, "then the return PC");
    chk(e_sp_out === 32'h0000_0274, "three words, where an interrupt pushed two");
    chk(e_psw_out[PSW_IE] === 1'b0, "Figure 8-5 disables interrupts for it");
    chk(e_psw_out[PSW_IS] === 1'b1,
        "and its information still goes on the interrupt stack");

    // 64 is the first vector an application may supply, and is not invalid.
    e_sp        = 32'h0000_0200;
    iack_second = 8'd64;
    put_word(13'h1000 + 13'd256, 32'h0000_2400);
    take;
    chk(!e_invalid,               "vector 64 is the first one an application owns");
    chk(e_handler === 32'h0000_2400, "and it reads its own entry");
    e_ackv = 1'b0; e_int = 1'b0; e_ist = 1'b0;

    // =======================================================================
    // The bus fault frame, which is the only one in this tree with a parameter
    // word above the code: Figure 8-5's "#3 Bus Fault, +12 Exception Address,
    // +8 Exception Code | 8, +4 PSW, 0 PC", with the note that the exception
    // address is a physical address.
    // =======================================================================
    e_vec  = 8'd3;
    e_sp   = 32'h0000_0180;
    e_np   = 2'd1;
    e_p0   = 32'h00AB_CDEF;           // the address of the cycle that failed
    e_code = 16'h0313;                // fixed length data read bus error
    e_dis  = 1'b1;                    // "interrupts disabled"
    e_ist  = 1'b1;                    // "pushed onto the interrupt stack"
    take;
    chk(e_handler === 32'h0000_7000, "the bus fault handler is vector 3's entry");
    chk(word_at(13'h17C) === 32'h00AB_CDEF,
        "the Exception Address is pushed first, deepest in the frame");
    chk(word_at(13'h178) === 32'h0313_0008,
        "then the code beside a parameter count of 8: two words, eight bytes");
    chk(word_at(13'h174) === e_psw,         "then the PSW");
    chk(word_at(13'h170) === 32'h0000_0110, "then the PC");
    chk(e_sp_out === 32'h0000_0170,  "four words of frame");
    chk(e_psw_out[PSW_IE] === 1'b0,  "a bus error disables maskable interrupts");
    chk(e_psw_out[PSW_IS] === 1'b1,
        "and it runs on the interrupt stack, though it is not an interrupt");
    e_dis = 1'b0; e_ist = 1'b0; e_np = 2'd0;

    if (errors == 0) $display("V60 EXC PASS");
    else             $display("V60 EXC FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #20_000_000;
    $display("V60 EXC FAIL (timeout)");
    $finish;
end

endmodule
