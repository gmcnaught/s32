library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_upd7725_lab is end;
architecture test of tb_upd7725_lab is
	signal clk : std_logic := '0'; signal ce, reset_n, int_i : std_logic := '0';
	signal pwe,dwe,hwe,hre : std_logic := '0';
	signal pa,pc : std_logic_vector(10 downto 0):=(others=>'0'); signal da : std_logic_vector(9 downto 0):=(others=>'0');
	signal pd,ir : std_logic_vector(23 downto 0):=(others=>'0'); signal dd,hw,hr : std_logic_vector(15 downto 0):=(others=>'0');
	signal p0,p1,dma,ei,rqm : std_logic; signal aa,ab,dp,rp,dr,sr : std_logic_vector(15 downto 0);
	signal fa,fb : std_logic_vector(5 downto 0); signal sp : std_logic_vector(3 downto 0);
	function ld(v:natural; dst:natural) return std_logic_vector is begin return "11"&std_logic_vector(to_unsigned(v,16))&"00"&std_logic_vector(to_unsigned(dst,4)); end;
	function op(alu,p,a,src,dst:natural) return std_logic_vector is variable x:unsigned(23 downto 0):=(others=>'0');begin x(21 downto 20):=to_unsigned(p,2);x(19 downto 16):=to_unsigned(alu,4);x(15):=to_unsigned(a,1)(0);x(7 downto 4):=to_unsigned(src,4);x(3 downto 0):=to_unsigned(dst,4);return std_logic_vector(x);end;
	function jp(target:natural) return std_logic_vector is variable x:unsigned(23 downto 0):=(others=>'0');begin x(23 downto 22):="10";x(21 downto 20):="10";x(12 downto 2):=to_unsigned(target,11);return std_logic_vector(x);end;
	function rt return std_logic_vector is variable x:unsigned(23 downto 0):=(others=>'0');begin x(23 downto 22):="01";return std_logic_vector(x);end;
	procedure load(signal a:out std_logic_vector(10 downto 0);signal d:out std_logic_vector(23 downto 0);signal we:out std_logic; n:natural;v:std_logic_vector) is begin a<=std_logic_vector(to_unsigned(n,11));d<=v;we<='1';wait until rising_edge(clk);we<='0';end;
begin
	clk<=not clk after 5 ns;
	dut:entity work.upd7725_lab port map(clk=>clk,ce=>ce,reset_n=>reset_n,int_i=>int_i,prog_load_we=>pwe,prog_load_addr=>pa,prog_load_data=>pd,data_load_we=>dwe,data_load_addr=>da,data_load_data=>dd,host_dr_we=>hwe,host_dr_re=>hre,host_dr_wdata=>hw,host_dr_rdata=>hr,p0_o=>p0,p1_o=>p1,dma_o=>dma,ei_o=>ei,rqm_o=>rqm,dbg_pc=>pc,dbg_ir=>ir,dbg_acca=>aa,dbg_accb=>ab,dbg_dp=>dp,dbg_rp=>rp,dbg_dr=>dr,dbg_sr=>sr,dbg_flaga=>fa,dbg_flagb=>fb,dbg_sp=>sp);
	process begin
		-- Runtime program/data loading while execution is disabled, then reset.
		reset_n<='1';
		load(pa,pd,pwe,0,ld(3,1)); load(pa,pd,pwe,1,ld(4,3));
		load(pa,pd,pwe,2,op(5,1,0,3,0)); -- ACCA += TR
		load(pa,pd,pwe,3,ld(16#0883#,7)); -- DMA, EI, P1, P0
		load(pa,pd,pwe,4,ld(16#55AA#,6)); -- DR and RQM
		load(pa,pd,pwe,5,ld(16#0012#,5)); -- RP
		load(pa,pd,pwe,6,op(0,1,0,6,2)); -- data ROM -> ACCB
		load(pa,pd,pwe,7,jp(9)); load(pa,pd,pwe,8,ld(16#DEAD#,3)); load(pa,pd,pwe,9,ld(16#BEEF#,3));
		load(pa,pd,pwe,16#100#,rt);
		da<=std_logic_vector(to_unsigned(16#12#,10));dd<=x"CAFE";dwe<='1';wait until rising_edge(clk);dwe<='0';
		wait until falling_edge(clk); reset_n<='0'; wait until falling_edge(clk); reset_n<='1';ce<='1';
		for i in 1 to 7 loop wait until rising_edge(clk); wait for 1 ns; end loop;
		assert pc=std_logic_vector(to_unsigned(7,11)) report "fetch/PC failed" severity failure;
		assert aa=x"0007" report "arithmetic failed" severity failure;
		assert ab=x"CAFE" report "data ROM load/read failed" severity failure;
		assert p0='1' and p1='1' and dma='1' and ei='1' report "status visibility failed" severity failure;
		assert dr=x"55AA" and rqm='1' and hr=x"55AA" report "DR/RQM failed" severity failure;
		wait until rising_edge(clk);wait for 1 ns;assert pc=std_logic_vector(to_unsigned(9,11)) report "unconditional control transfer failed" severity failure;
		hre<='1';wait until rising_edge(clk);wait for 1 ns;hre<='0';assert rqm='0' report "host DR acknowledge failed" severity failure;
		hw<=x"1234";hwe<='1';wait until rising_edge(clk);wait for 1 ns;hwe<='0';assert dr=x"1234" report "host DR write failed" severity failure;
		-- MAME generic chip sequence: EI-qualified rising edge, NOP, LCALL $100.
		int_i<='1';wait until rising_edge(clk);wait for 1 ns;assert ei='0' report "interrupt did not clear EI" severity failure;
		wait until rising_edge(clk);wait until rising_edge(clk);wait for 1 ns;
		assert pc=std_logic_vector(to_unsigned(16#100#,11)) and sp=x"1" report "interrupt NOP/LCALL sequence failed" severity failure;
		wait until rising_edge(clk);wait for 1 ns;assert sp=x"0" report "RT stack pop failed" severity failure;
		report "PASS tb_upd7725_lab" severity note; std.env.stop;
	end process;
end;
