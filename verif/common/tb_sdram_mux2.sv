`timescale 1ns/1ps
module tb_sdram_mux2;
reg clk=0, rst=1; always #5 clk=~clk;
reg mr=0, mb=0, sr=0, sb=0, ma_ack=0;
reg [24:1] mad=0, sad=0;
reg [63:0] mdout=0;
wire [63:0] mdo,sdo; wire mack,sack,req,burst; wire [24:1] addr;
integer errors=0;
s32_sdram_mux2 dut(.clk(clk),.rst(rst),.main_req(mr),.main_burst(mb),.main_addr(mad),
 .main_dout(mdo),.main_ack(mack),.sub_req(sr),.sub_burst(sb),.sub_addr(sad),
 .sub_dout(sdo),.sub_ack(sack),.mem_req(req),.mem_burst(burst),.mem_addr(addr),
 .mem_dout(mdout),.mem_ack(ma_ack));
task ck(input ok,input[255:0] label); begin if(!ok) begin errors=errors+1;$display("FAIL %0s",label);end end endtask
task ack_cycle(input [63:0] data); begin
 @(negedge clk); mdout=data; ma_ack=1; #1;
 @(posedge clk); #1; ma_ack=0;
end endtask
initial begin
 repeat(3) @(posedge clk); rst<=0;
 // Simultaneous first requests: main wins, and controls remain latched.
 @(negedge clk); mr=1;sr=1;mb=1;sb=0;mad=24'h123456;sad=24'h654321;
 @(posedge clk);#1;ck(req&&addr==24'h123456&&burst,"first main grant");
 mad=24'hffffff;mb=0; #1;ck(addr==24'h123456&&burst,"latched controls");
 @(negedge clk);mdout=64'h1111222233334444;ma_ack=1;#1;
 ck(mack&&!sack&&mdo==64'h1111222233334444&&sdo==0,"main-only ack/data");
 @(posedge clk);#1;ma_ack=0;mr=0;
 @(posedge clk);#1;ck(!req&&!mack&&!sack,"required downstream low gap");
 // Waiting sub is granted next. Holding its request through ack cannot retrigger.
 @(posedge clk);#1;ck(req&&addr==24'h654321&&!burst,"waiting sub grant");
 @(negedge clk);mdout=64'haabbccddeeff0011;ma_ack=1;#1;
 ck(sack&&!mack&&sdo==64'haabbccddeeff0011&&mdo==0,"sub-only ack/data");
 @(posedge clk);#1;ma_ack=0;
 repeat(3) @(posedge clk);#1;ck(!req,"held requester not retriggered");
 @(negedge clk);sr=0; @(posedge clk); @(negedge clk);sr=1;sad=24'h000077;
 @(posedge clk);#1;ck(req&&addr==24'h000077,"drop rearms requester");
 @(negedge clk);ma_ack=1;#1;@(posedge clk);#1;ma_ack=0;sr=0;
 // After sub was last, simultaneous fresh requests select main (RR fairness).
 repeat(2) @(posedge clk); @(negedge clk);mr=1;sr=1;mad=24'h0000aa;sad=24'h0000bb;
 @(posedge clk);#1;ck(req&&addr==24'h0000aa,"round robin main after sub");
 if(errors==0)$display("SDRAM MUX2 PASS");else $display("SDRAM MUX2 FAIL (%0d errors)",errors);
 $finish;
end
initial begin #10000;$display("SDRAM MUX2 FAIL timeout");$finish;end
endmodule
