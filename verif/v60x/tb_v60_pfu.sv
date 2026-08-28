//============================================================================
//  tb_v60_pfu -- the instruction stream, and who gets the bus while it fills.
//
//  v60_pfu and a stand-in data requester both go through v60_bus_arb into a
//  real v60_biu and the two-bank memory model.  The bench watches the STATUS
//  of every bus cycle, which is the only place the difference between a
//  prefetch, a demand fetch and a data access is visible -- and which is
//  exactly what the databook specifies about this unit.
//
//  Checked here:
//    the queue is sixteen bytes and stops fetching when it is full
//    bytes come out in program order, with the PC of each
//    the first fetch after a flush is a DEMAND fetch, the rest are PREFETCH
//    a control transfer flushes, including one already on the bus
//    a fetch to an odd target drops the byte before it
//    no prefetch cycle ever happens while the data unit wants the bus
//============================================================================
`timescale 1ns/1ps

module tb_v60_pfu;
    import v60_bus_pkg::*;

localparam integer DIV = 6;

reg clk = 1'b0;
always #5 clk = ~clk;

reg rst = 1'b1;

reg [2:0] tick = 3'd0;
always @(posedge clk) if (!rst) tick <= (tick == DIV-1) ? 3'd0 : tick + 3'd1;
wire ce_rise = !rst && (tick == 3'd0);
wire ce_fall = !rst && (tick == DIV/2);

// ---- prefetch unit ---------------------------------------------------------
reg          redirect = 1'b0, byte_take = 1'b0;
reg   [31:0] redirect_pc = 32'd0;

wire   [7:0] byte_out;
wire         byte_valid;
wire  [31:0] byte_pc;
wire   [4:0] level;

wire         p_req, p_ack;
bus_status_e p_status;
wire  [23:0] p_addr;
wire   [1:0] p_dl;
wire  [15:0] biu_rdata;

v60_pfu dut (
    .clk(clk), .rst(rst),
    .byte_out(byte_out), .byte_valid(byte_valid), .byte_take(byte_take),
    .byte_pc(byte_pc),
    .redirect(redirect), .redirect_pc(redirect_pc),
    .bus_req(p_req), .bus_status(p_status), .bus_addr(p_addr), .bus_dl(p_dl),
    .bus_ack(p_ack), .bus_rdata(biu_rdata),
    .level(level)
);

// ---- a stand-in for the data unit ------------------------------------------
// It holds its request the way v60_dxu does: up until the ack of the last bus
// cycle of a logical access.
reg         d_go = 1'b0;
reg  [23:0] d_addr = 24'h000800;
// The data unit's status is a reg so the bench can put a THIRD kind of cycle on
// the bus: the interrupt acknowledge, which is neither a data access nor an
// instruction fetch and which nothing above this bench exercises here.
bus_status_e d_status = BST_MEM_SINGLE;
wire        d_ack;
reg         d_req = 1'b0;

always @(posedge clk) begin
    if (rst)          d_req <= 1'b0;
    else if (d_go)    d_req <= 1'b1;
    else if (d_ack)   d_req <= 1'b0;
    else if (!d_go)   d_req <= 1'b0;
end

// ---- arbiter and bus -------------------------------------------------------
wire         biu_req, biu_we, biu_ube, biu_first, biu_ack, biu_busy, own_pfu;
bus_status_e biu_status;
wire  [23:0] biu_addr;
wire   [1:0] biu_dl;
wire  [15:0] biu_wdata;

v60_bus_arb arb (
    .clk(clk), .rst(rst),
    .d_req(d_req), .d_status(d_status), .d_addr(d_addr), .d_we(1'b0),
    .d_dl(DL_HALFWORD), .d_ube(1'b0), .d_first(1'b1), .d_wdata(16'd0),
    .d_ack(d_ack),
    .p_req(p_req), .p_status(p_status), .p_addr(p_addr), .p_dl(p_dl),
    .p_ack(p_ack),
    .biu_req(biu_req), .biu_status(biu_status), .biu_addr(biu_addr),
    .biu_we(biu_we), .biu_dl(biu_dl), .biu_ube(biu_ube), .biu_first(biu_first),
    .biu_wdata(biu_wdata), .biu_ack(biu_ack), .biu_busy(biu_busy),
    .own_pfu(own_pfu)
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
    .dl(biu_dl), .ube(biu_ube), .first(biu_first), .wdata(biu_wdata),
    .ack(biu_ack), .rdata(biu_rdata), .busy(biu_busy),
    .a(a), .dl_o(dl_o), .st(st), .mrq_n(mrq_n), .rw_n(rw_n), .ube_n(ube_n),
    .fas_n(fas_n), .bcy_n(bcy_n), .ds_n(ds_n),
    .d_out(d_out), .d_oe(d_oe), .d_in(d_in), .bus_hiz(bus_hiz),
    .ready_n(1'b0), .bmode(1'b1), .hldrq_n(1'b1), .hldak_n(hldak_n),
    .berr_n(1'b1), .rt_ep_n(1'b1), .nmi_n(1'b1), .int_req(1'b0),
    .berr(), .berr_status(), .berr_addr(), .berr_we(), .berr_retry(),
    .nmi_pending(), .nmi_take(1'b0), .int_pending(),
    .state(state)
);

reg  [7:0] mem [0:2047];
wire [10:0] bank_even = {a[10:1], 1'b0};
always @(*) d_in = {mem[bank_even + 11'd1], mem[bank_even]};

// ---- the recorder: one entry per bus cycle ---------------------------------
reg  [23:0] rec_a  [0:63];
reg   [3:0] rec_st [0:63];
integer     ncyc = 0;

always @(posedge clk) if (!rst && biu_ack) begin
    if (ncyc < 64) begin
        rec_a[ncyc]  = a;
        rec_st[ncyc] = {mrq_n, st};
    end
    ncyc = ncyc + 1;
end

integer errors = 0;

// ---- always-on properties of the arbiter -----------------------------------
// An ack belongs to whoever asked for that cycle, and ownership cannot change
// while the cycle is running: v60_biu asserts BCY* at the rising edge of T1 and
// negates it at the rising edge of T4 (p.3.283), and there is no way to abort
// what is in between.
reg own_at_start = 1'b0;
reg in_cycle     = 1'b0;

always @(posedge clk) if (!rst) begin
    if (!bcy_n && !in_cycle) begin
        in_cycle     = 1'b1;
        own_at_start = own_pfu;
    end
    if (in_cycle && (own_pfu !== own_at_start)) begin
        errors = errors + 1;
        $display("FAIL  the bus changed owner while a cycle was running (t=%0t)", $time);
        own_at_start = own_pfu;
    end
    if (biu_ack) begin
        if (d_ack && p_ack) begin
            errors = errors + 1;
            $display("FAIL  one ack reached both masters (t=%0t)", $time);
        end
        if (d_ack && own_pfu) begin
            errors = errors + 1;
            $display("FAIL  a prefetch cycle acked the data unit (t=%0t)", $time);
        end
        if (p_ack && !own_pfu) begin
            errors = errors + 1;
            $display("FAIL  a data cycle acked the prefetch unit (t=%0t)", $time);
        end
        in_cycle = 1'b0;
    end
end

task chk(input cond, input [8*72:1] what);
begin
    if (!cond) begin
        errors = errors + 1;
        $display("FAIL  %0s (t=%0t)", what, $time);
    end
end
endtask

// Take one byte off the queue and return it.
reg [7:0] got;
reg [31:0] got_pc;
task take;
begin
    while (!byte_valid) @(negedge clk);
    got    = byte_out;
    got_pc = byte_pc;
    // The invariant behind every test here: whatever byte comes out, it is the
    // one in memory at the address the unit says it came from.
    chk(got === mem[got_pc[10:0]], "a delivered byte is the memory at its own PC");
    byte_take = 1'b1;
    @(negedge clk);
    byte_take = 1'b0;
end
endtask

// Wait until the bus goes quiet, so that a test that follows sees only the
// cycles it caused.  The bus goes quiet because the queue fills and the unit
// stops asking, which is itself one of the properties under test.
task quiesce;
    integer mark;
begin
    mark = -1;
    repeat (60) @(negedge clk);
    while (ncyc != mark) begin
        mark = ncyc;
        repeat (60) @(negedge clk);
    end
end
endtask

task jump(input [31:0] pc);
begin
    @(negedge clk);
    redirect_pc = pc;
    redirect    = 1'b1;
    @(negedge clk);
    redirect = 1'b0;
end
endtask

integer i, n_prefetch, n_demand, n_data;
reg [31:0] prev_pc;

initial begin
    for (i = 0; i < 2048; i = i + 1) mem[i] = i[7:0] ^ 8'h5A;

    repeat (4) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);

    // =======================================================================
    // A control transfer to 0x100, and the first fetch after it.
    // =======================================================================
    // After reset the unit is already fetching from its reset PC; let that
    // settle so the cycles below are the ones this control transfer caused.
    quiesce;
    ncyc = 0;
    jump(32'h00000100);
    while (ncyc < 1) @(negedge clk);
    chk(rec_st[0] === BST_DEMAND_FETCH, "the fetch after a flush is a demand fetch");
    chk(rec_a[0] === 24'h000100,        "and it starts at the target");

    while (ncyc < 4) @(negedge clk);
    chk(rec_st[1] === BST_PREFETCH && rec_st[2] === BST_PREFETCH,
                                        "the fetches after that one are prefetches");
    chk(rec_a[1] === 24'h000102 && rec_a[2] === 24'h000104,
                                        "and they walk forward a halfword at a time");

    // =======================================================================
    // Sixteen bytes, and then it stops.
    // =======================================================================
    quiesce;
    chk(level === 5'd16, "the queue holds sixteen bytes");
    ncyc = 0;
    repeat (400) @(negedge clk);
    chk(ncyc == 0, "a full queue makes no bus cycles at all");

    // The bytes are the program, in order, each with its own PC.
    for (i = 0; i < 16; i = i + 1) begin
        take;
        chk(got === mem[11'h100 + i[10:0]], "the queue delivers the program in order");
        chk(got_pc === (32'h00000100 + i[31:0]), "and the PC of each byte with it");
    end

    // Emptying it starts the fetching again.
    ncyc = 0;
    while (level < 5'd8) @(negedge clk);
    chk(ncyc > 0, "an emptied queue fills again");

    // =======================================================================
    // A control transfer while the queue is full and a fetch may be in flight.
    // =======================================================================
    quiesce;
    ncyc = 0;
    jump(32'h00000200);
    take;
    chk(got === mem[11'h200],        "after a control transfer the stream is the new one");
    chk(got_pc === 32'h00000200,     "and the PC follows it");
    chk(rec_st[0] === BST_DEMAND_FETCH || rec_st[1] === BST_DEMAND_FETCH,
                                     "a flushed queue demands its first fetch");

    // =======================================================================
    // An odd target.  The bus can only fetch an aligned halfword, so the byte
    // before the target must not reach the decoder.
    // =======================================================================
    quiesce;
    ncyc = 0;
    jump(32'h00000301);
    take;
    chk(got === mem[11'h301],    "an odd target delivers the byte AT the target first");
    chk(got_pc === 32'h00000301, "with its own PC");
    chk(rec_a[0] === 24'h000300, "and the bus cycle that fetched it was aligned");
    take;
    chk(got === mem[11'h302],    "and the stream continues from there");

    // A consequence of only ever fetching an aligned halfword: an odd stream
    // leaves one slot that cannot be filled, so the queue rests at fifteen.
    quiesce;
    chk(level === 5'd15, "an odd instruction stream rests at fifteen queued bytes");

    // =======================================================================
    // "As the lowest priority bus requester, the PFU uses otherwise idle bus
    // cycles" -- p.3.246.  While the data unit is asking, nothing else runs.
    // =======================================================================
    // Drain the queue so the prefetch unit is definitely trying to fetch.
    for (i = 0; i < 16; i = i + 1) if (byte_valid) take;

    ncyc  = 0;
    d_go  = 1'b1;
    repeat (600) @(negedge clk);
    d_go  = 1'b0;

    // A bus cycle already granted when the data unit arrives finishes -- there
    // is no way to abort one, and "lowest priority" is about who is granted the
    // NEXT cycle.  So the property is: once the data unit has had a cycle, it
    // has every cycle until it stops asking.
    n_prefetch = 0; n_demand = 0; n_data = 0;
    for (i = 0; i < ncyc && i < 64; i = i + 1) begin
        if (rec_st[i] === BST_MEM_SINGLE) n_data = n_data + 1;
        else if (n_data > 0) begin
            if (rec_st[i] === BST_PREFETCH)          n_prefetch = n_prefetch + 1;
            else if (rec_st[i] === BST_DEMAND_FETCH) n_demand   = n_demand + 1;
        end
    end
    chk(n_data > 1,                       "the data unit got the bus, repeatedly");
    chk(n_prefetch == 0 && n_demand == 0, "and no instruction fetch ran while it wanted it");

    // Releasing it hands the bus straight back.
    ncyc = 0;
    repeat (200) @(negedge clk);
    n_prefetch = 0;
    for (i = 0; i < ncyc && i < 64; i = i + 1)
        if (rec_st[i] === BST_PREFETCH || rec_st[i] === BST_DEMAND_FETCH)
            n_prefetch = n_prefetch + 1;
    chk(n_prefetch > 0, "and the prefetch unit resumes on the idle bus");

    // =======================================================================
    // A control transfer while a fetch is ON THE BUS.  v60_biu cannot abort a
    // cycle -- it runs T1 T2 T3 T4 once started (p.3.283) -- so the halfword
    // comes back after the queue it was fetched for is gone.
    // =======================================================================
    d_go = 1'b0;
    quiesce;
    for (i = 0; i < 20; i = i + 1) if (byte_valid) take;   // drain, so it fetches
    while (!(bcy_n === 1'b0 && own_pfu === 1'b1)) @(negedge clk);
    jump(32'h00000400);
    take;
    chk(got === mem[11'h400],    "a fetch already on the bus does not reach the flushed queue");
    chk(got_pc === 32'h00000400, "and the PC is the target, not the stale stream");
    take;
    chk(got === mem[11'h401],    "the stream after it is the new one");

    // =======================================================================
    // The data unit arrives while a fetch is on the bus.  The grant is held to
    // the ack, so the fetch finishes as a fetch and its data reaches the queue
    // -- an ack delivered to the wrong master loses a halfword and stalls the
    // unit that was waiting for it.
    // =======================================================================
    quiesce;
    for (i = 0; i < 20; i = i + 1) if (byte_valid) take;
    while (!(bcy_n === 1'b0 && own_pfu === 1'b1)) @(negedge clk);
    d_go = 1'b1;
    repeat (200) @(negedge clk);
    d_go = 1'b0;
    take;
    prev_pc = got_pc;
    take;
    chk(got_pc === prev_pc + 32'd1,
        "the fetch in flight when the data unit arrived was not lost");

    // =======================================================================
    // A data request WITHDRAWN in the middle of its own bus cycle, while the
    // prefetch unit is waiting.  The cycle still belongs to the data unit
    // until T4; handing the bus over here would give its read to the prefetch
    // queue.  (v60_dxu holds its request to the ack, so this is the arbiter
    // being made to survive a master that does not.)
    // =======================================================================
    quiesce;
    for (i = 0; i < 20; i = i + 1) if (byte_valid) take;   // the PFU wants the bus
    d_go = 1'b1;
    while (!(bcy_n === 1'b0 && own_pfu === 1'b0)) @(negedge clk);
    d_go = 1'b0;                                          // withdraw, mid-cycle
    repeat (40) @(negedge clk);
    take;
    prev_pc = got_pc;
    take;
    chk(got_pc === prev_pc + 32'd1,
        "the stream survives a data request withdrawn mid-cycle");

    // =======================================================================
    // The other half of the same rule: a request that disappears BEFORE its
    // cycle starts has to release the grant, or the bus is held for a cycle
    // that will never run and nothing else can ever be granted.
    // =======================================================================
    quiesce;                       // the queue is full, so only the data unit asks
    d_go = 1'b1;
    @(negedge clk);
    d_go = 1'b0;                   // gone again before v60_biu reaches T1
    for (i = 0; i < 20; i = i + 1) if (byte_valid) take;
    while (level < 5'd8) @(negedge clk);    // wedged if the grant was kept
    chk(level >= 5'd8, "a request withdrawn before its cycle started does not wedge the bus");

    // =======================================================================
    // A third kind of cycle.  The arbiter's two invariants -- ownership does
    // not change between BCY* and the ack, and an ack reaches exactly one
    // master -- are held continuously by the monitor above, and they are held
    // over whatever status is on the pins.  An interrupt acknowledge is the
    // case worth running because it is the one status that is neither of the
    // two the rest of this bench sees, and because it is an I/O cycle, so the
    // three-TI recovery gap runs between consecutive ones while the prefetch
    // unit is asking for the bus.
    // =======================================================================
    d_go = 1'b0;
    quiesce;
    for (i = 0; i < 16; i = i + 1) if (byte_valid) take;

    ncyc     = 0;
    d_status = BST_INTERRUPT_ACK;
    d_go     = 1'b1;
    repeat (600) @(negedge clk);
    d_go     = 1'b0;
    repeat (200) @(negedge clk);
    d_status = BST_MEM_SINGLE;

    n_data = 0; n_prefetch = 0;
    for (i = 0; i < ncyc && i < 64; i = i + 1) begin
        if (rec_st[i] === BST_INTERRUPT_ACK)             n_data     = n_data + 1;
        else if (rec_st[i] === BST_PREFETCH ||
                 rec_st[i] === BST_DEMAND_FETCH)         n_prefetch = n_prefetch + 1;
    end
    chk(n_data > 1,     "interrupt acknowledge cycles ran on the bus");
    chk(n_prefetch > 0, "with the prefetch unit taking the gaps between them");

    if (errors == 0) $display("V60 PFU PASS");
    else             $display("V60 PFU FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #40_000_000;
    $display("V60 PFU FAIL (timeout)");
    $finish;
end

endmodule
