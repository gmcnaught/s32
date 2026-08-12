`timescale 1ns/1ps
module tb_v60_dualctx;
reg clk=0; always #5 clk=~clk;
reg rst0=1, rst1=1;
reg ack0=0, ack1=0;
wire req0,req1,we0,we1,ctx,ia0,ia1,qa0,qa1;
wire [31:0] a0,a1,w0,w1; wire [1:0] s0,s1; wire [23:0] fa0,fa1;
integer c0=0,c1=0;
s32_v60_dualctx dut(
 .clk(clk),.ce0(1'b1),.rst0(rst0),.fast_ifetch0(1'b0),.irq_n0(1'b1),.irq_vector0(8'h11),.nmi_n0(1'b1),.irq_ack0(qa0),
 .if_req0(ia0),.if_addr0(fa0),.if_data0(64'd0),.if_ack0(1'b0),.bus_req0(req0),.bus_we0(we0),.bus_addr0(a0),.bus_size0(s0),.bus_wdata0(w0),.bus_rdata0(32'h11112222),.bus_ack0(ack0),
 .ce1(1'b1),.rst1(rst1),.fast_ifetch1(1'b0),.irq_n1(1'b1),.irq_vector1(8'h22),.nmi_n1(1'b1),.irq_ack1(qa1),
 .if_req1(ia1),.if_addr1(fa1),.if_data1(64'd0),.if_ack1(1'b0),.bus_req1(req1),.bus_we1(we1),.bus_addr1(a1),.bus_size1(s1),.bus_wdata1(w1),.bus_rdata1(32'h33334444),.bus_ack1(ack1),.active_context(ctx));
always @(posedge clk) if(ctx)c1=c1+1; else c0=c0+1;
initial begin
 repeat(6) @(posedge clk); rst0=0; rst1=0;
 // Write distinct architectural and microarchitectural values into each live
 // slot; the generated exchange must preserve them without cross-state.
 wait(ctx==0); @(posedge clk); #1 dut.engine.pc=32'h10001000; dut.engine.r[5]=32'ha0a0a0a0; dut.engine.mdcnt=6'd7;
 wait(ctx==1); @(posedge clk); #1 dut.engine.pc=32'h20002000; dut.engine.r[5]=32'hb1b1b1b1; dut.engine.mdcnt=6'd19;
 wait(ctx==0); #1;
 if(dut.engine.pc!==32'h10001000 || dut.engine.r[5]!==32'ha0a0a0a0 || dut.engine.mdcnt!==7) $fatal(1,"context 0 state crossed");
 wait(ctx==1); #1;
 if(dut.engine.pc!==32'h20002000 || dut.engine.r[5]!==32'hb1b1b1b1 || dut.engine.mdcnt!==19) $fatal(1,"context 1 state crossed");
 // Inject simultaneous engine issues on their respective slots.  Each wrapper
 // request must remain asserted with an immutable payload while the other
 // context runs, and late acknowledgements must set only the issuer response.
 force dut.core_bus_req=0; force dut.core_bus_we=1; force dut.core_bus_size=2;
 dut.bus_pending=0; dut.bus_response=0;
 wait(ctx==0); force dut.core_bus_addr=32'h01000100; force dut.core_bus_wdata=32'haaaa0000; force dut.core_bus_req=1; @(posedge clk); #1; force dut.core_bus_req=0;
 wait(ctx==1); force dut.core_bus_addr=32'h02000200; force dut.core_bus_wdata=32'hbbbb0000; force dut.core_bus_req=1; @(posedge clk); #1; force dut.core_bus_req=0;
 if(!req0 || !req1 || a0!==32'h01000100 || a1!==32'h02000200 || w0!==32'haaaa0000 || w1!==32'hbbbb0000) begin
   $display("req=%b%b a=%h/%h w=%h/%h ctx=%b",req1,req0,a0,a1,w0,w1,ctx);
   $fatal(1,"tagged request/payload failure");
 end
 @(negedge clk); ack0=1; @(posedge clk); #1; ack0=0;
 if(dut.bus_response[0]!==1 || dut.bus_response[1]!==0) begin $display("responses=%b pending=%b ctx=%b",dut.bus_response,dut.bus_pending,ctx); $fatal(1,"late ack routed to wrong issuer"); end
 release dut.core_bus_req; release dut.core_bus_we; release dut.core_bus_size; release dut.core_bus_addr; release dut.core_bus_wdata;
 repeat(8) @(posedge clk);
 if((c0-c1>1)||(c1-c0>1)) $fatal(1,"cadence mismatch %0d/%0d",c0,c1);
 $display("V60 DUALCTX PASS cadence=%0d/%0d",c0,c1); $finish;
end
initial begin #10000 $fatal(1,"timeout"); end
endmodule
