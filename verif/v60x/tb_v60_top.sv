//============================================================================
//  tb_v60_top -- the assembled core runs a generated program off its pins.
//
//  The program is one of verif/cosim/gen_diff_program.py's: forty random
//  register-to-register ALU operations on R0..R7, GETPSW into R7, R0..R7
//  stored to 0x8000, HALT.  The generator also writes the reference model's
//  expected final state, and verif/v60x/run_v60x.sh compares this bench's
//  R%0d= / M%0d= lines against it -- the same contract tb_v60_diff.sv has
//  with the shipping core, so the two cores can be held to one file.
//
//  Memory is two byte-wide banks reached only through the three legal
//  {UBE*, A0} lane encodings (databook p.3.236), as tb_v60_seq models it, so
//  a wrong lane moves the wrong byte rather than merely looking wrong.
//
//  What this bench proves is narrow on purpose: the top level is wired the
//  way the sequencer bench was wired, and a program placed by START_PC runs
//  to HALT.  Semantics are tb_v60_seq's business and the lockstep bench's.
//============================================================================
`timescale 1ns/1ps
module tb_v60_top;
    import v60_bus_pkg::*;

localparam integer DIV = 6;
reg clk = 1'b0;
always #5 clk = ~clk;
reg rst = 1'b1;
reg [2:0] tick = 3'd0;
always @(posedge clk) if (!rst) tick <= (tick == DIV-1) ? 3'd0 : tick + 3'd1;
wire ce_rise = !rst && (tick == 3'd0);
wire ce_fall = !rst && (tick == DIV/2);

wire [23:0] a;
wire  [1:0] dl_o;
wire  [2:0] st;
wire        mrq_n, rw_n, ube_n, fas_n, bcy_n, ds_n, block_n, hldak_n, bus_hiz;
wire [15:0] d_out;
wire        d_oe;
reg  [15:0] d_in;
wire [31:0] pc, psw;
wire        retired, halted, stopped, own_pfu;
wire  [1:0] stop_reason;
wire  [4:0] insn_cycles;
bus_state_e state;
reg         run = 1'b0;

v60_top #(.START_PC(32'h0000_0000)) dut (
    .clk(clk), .rst(rst), .ce_rise(ce_rise), .ce_fall(ce_fall), .run(run),
    .a(a), .dl_o(dl_o), .st(st), .mrq_n(mrq_n), .rw_n(rw_n), .ube_n(ube_n),
    .fas_n(fas_n), .bcy_n(bcy_n), .ds_n(ds_n), .block_n(block_n),
    .hldak_n(hldak_n), .bus_hiz(bus_hiz),
    .d_out(d_out), .d_oe(d_oe), .d_in(d_in),
    .ready_n(1'b0), .bmode(1'b1), .hldrq_n(1'b1), .berr_n(1'b1), .rt_ep_n(1'b1),
    .nmi_n(1'b1), .int_req(1'b0),
    .pc(pc), .psw(psw), .retired(retired), .halted(halted),
    .stopped(stopped), .stop_reason(stop_reason), .insn_cycles(insn_cycles),
    .state(state), .own_pfu(own_pfu),
    .pr_id(5'd0), .pr_wr(1'b0), .pr_wdata(32'd0)
);

// ---- memory: 64 KB, two byte banks, three lane encodings ----------------------
reg   [7:0] mem [65536];
wire [15:0] bank_even = {a[15:1], 1'b0};
always_comb d_in = {mem[bank_even + 16'd1], mem[bank_even]};

wire biu_ack = dut.u_biu.ack;
always @(posedge clk) if (!rst && biu_ack && !rw_n) begin
    case ({ube_n, a[0]})
        2'b00: begin mem[bank_even] = d_out[7:0];
                     mem[bank_even + 16'd1] = d_out[15:8]; end
        2'b01: mem[bank_even + 16'd1] = d_out[15:8];
        2'b10: mem[bank_even] = d_out[7:0];
        default: ;
    endcase
end

// ---- the program, as the generator writes it: 16-bit little-endian words ------
reg  [15:0] words [32768];
reg [1023:0] hexfile;
integer i, n_retired, idle, errors;
always @(posedge clk) if (!rst && retired) n_retired = n_retired + 1;

initial begin
    errors = 0; n_retired = 0; idle = 0;
    for (i = 0; i < 65536; i = i + 1) mem[i] = 8'h00;
    for (i = 0; i < 32768; i = i + 1) words[i] = 16'h0000;
    if (!$value$plusargs("hex=%s", hexfile)) begin
        $display("no +hex=");
        $finish;
    end
    $readmemh(hexfile, words);
    for (i = 0; i < 32768; i = i + 1) begin
        mem[2*i]     = words[i][7:0];
        mem[2*i + 1] = words[i][15:8];
    end

    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (DIV*4) @(negedge clk);
    run = 1'b1;

    // Run to HALT.  Bound the wait in retirements rather than cycles so that a
    // slow bus cannot fail the test, and a wedge cannot pass it.
    for (i = 0; i < 400000 && !halted && !stopped; i = i + 1) @(posedge clk);

    if (stopped) begin
        errors = errors + 1;
        $display("STOP reason=%0d at pc=%08x after %0d instructions", stop_reason, pc, n_retired);
    end
    if (!halted) begin
        errors = errors + 1;
        $display("no HALT after %0d cycles, %0d instructions, pc=%08x", i, n_retired, pc);
    end

    for (i = 0; i < 8; i = i + 1)
        $display("R%0d=%08x", i, dut.u_rf.gpr[i]);
    for (i = 0; i < 8; i = i + 1)
        $display("M%0d=%08x", i, {mem[16'h8000 + 4*i + 3], mem[16'h8000 + 4*i + 2],
                                  mem[16'h8000 + 4*i + 1], mem[16'h8000 + 4*i]});
    $display("instructions retired: %0d", n_retired);

    if (errors == 0) $display("V60 TOP PASS");
    else             $display("V60 TOP FAIL errors=%0d", errors);
    $finish;
end

endmodule
