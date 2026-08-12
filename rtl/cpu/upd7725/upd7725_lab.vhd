-- uPD77P25 firmware-execution laboratory (not connected to production RTL).
-- Adapted 2026 from SNES_MiSTer DSPn.vhd, commit
-- ac616cade7df274a491614e95765ba87164798c7, GNU GPL v3.
-- See README.md and COPYING for provenance and limitations.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity upd7725_lab is
	generic (
		PROGRAM_INIT_FILE : string := "";
		DATA_INIT_FILE    : string := ""
	);
	port (
		clk, ce, reset_n : in std_logic;
		int_i : in std_logic := '0';
		si_i : in std_logic_vector(15 downto 0) := (others => '0');
		siack_i, soack_i : in std_logic := '0';
		prog_load_we : in std_logic := '0';
		prog_load_addr : in std_logic_vector(10 downto 0) := (others => '0');
		prog_load_data : in std_logic_vector(23 downto 0) := (others => '0');
		data_load_we : in std_logic := '0';
		data_load_addr : in std_logic_vector(9 downto 0) := (others => '0');
		data_load_data : in std_logic_vector(15 downto 0) := (others => '0');
		host_dr_we, host_dr_re : in std_logic := '0';
		host_dr_wdata : in std_logic_vector(15 downto 0) := (others => '0');
		host_dr_rdata : out std_logic_vector(15 downto 0);
		p0_o, p1_o, dma_o, ei_o, rqm_o : out std_logic;
		dbg_pc : out std_logic_vector(10 downto 0);
		dbg_ir : out std_logic_vector(23 downto 0);
		dbg_acca, dbg_accb, dbg_dp, dbg_rp, dbg_dr, dbg_sr : out std_logic_vector(15 downto 0);
		dbg_flaga, dbg_flagb : out std_logic_vector(5 downto 0);
		dbg_sp : out std_logic_vector(3 downto 0)
	);
end entity;

architecture rtl of upd7725_lab is
	type prog_mem_t is array (0 to 2047) of std_logic_vector(23 downto 0);
	type data_mem_t is array (0 to 1023) of std_logic_vector(15 downto 0);
	type ram_t is array (0 to 2047) of std_logic_vector(15 downto 0);
	type stack_t is array (0 to 15) of unsigned(10 downto 0);
	type pair16_t is array (0 to 1) of std_logic_vector(15 downto 0);
	type pair6_t is array (0 to 1) of std_logic_vector(5 downto 0);

	impure function load_prog(name : string) return prog_mem_t is
		file f : text; variable l : line; variable m : prog_mem_t := (others => (others => '0'));
		variable v : std_logic_vector(23 downto 0); variable i : natural := 0;
	begin
		if name /= "" then file_open(f, name, read_mode); while not endfile(f) and i < m'length loop readline(f,l); hread(l,v); m(i):=v; i:=i+1; end loop; file_close(f); end if; return m;
	end;
	impure function load_data(name : string) return data_mem_t is
		file f : text; variable l : line; variable m : data_mem_t := (others => (others => '0'));
		variable v : std_logic_vector(15 downto 0); variable i : natural := 0;
	begin
		if name /= "" then file_open(f, name, read_mode); while not endfile(f) and i < m'length loop readline(f,l); hread(l,v); m(i):=v; i:=i+1; end loop; file_close(f); end if; return m;
	end;

	signal pmem : prog_mem_t := load_prog(PROGRAM_INIT_FILE);
	signal drom : data_mem_t := load_data(DATA_INIT_FILE);
	signal dram : ram_t := (others => (others => '0'));
	signal stack : stack_t := (others => (others => '0'));
	signal acc : pair16_t := (others => (others => '0'));
	signal flags : pair6_t := (others => (others => '0'));
	signal pc : unsigned(10 downto 0) := (others => '0');
	signal sp : unsigned(3 downto 0) := (others => '0');
	signal dp : unsigned(10 downto 0) := (others => '0');
	signal rp : unsigned(10 downto 0) := (others => '1');
	signal tr, trb, dr, so, k, lreg : std_logic_vector(15 downto 0) := (others => '0');
	signal p0, p1, dma, ei, rqm, drc, usf0, usf1 : std_logic := '0';
	signal irq_last : std_logic := '0';
	signal irq_phase : unsigned(1 downto 0) := (others => '0');
	signal ir, idb, alu_p, alu_q, alu_r, mult_m, mult_n, sr, sgn, si_rev : std_logic_vector(15 downto 0);
	signal instr : std_logic_vector(23 downto 0) := (others => '0');
begin
	instr <= x"000000" when irq_phase=1 else x"A80400" when irq_phase=2 else pmem(to_integer(pc));
	sgn <= x"8000" when flags(0)(5)='0' else x"7FFF";
	rev_si:for j in 0 to 15 generate si_rev(j)<=si_i(15-j);end generate;
	idb <= trb when instr(7 downto 4)=x"0" else acc(0) when instr(7 downto 4)=x"1" else
		acc(1) when instr(7 downto 4)=x"2" else tr when instr(7 downto 4)=x"3" else
		"00000" & std_logic_vector(dp) when instr(7 downto 4)=x"4" else
		"000000" & std_logic_vector(rp(9 downto 0)) when instr(7 downto 4)=x"5" else
		drom(to_integer(rp(9 downto 0))) when instr(7 downto 4)=x"6" else
		sgn when instr(7 downto 4)=x"7" else
		dr when instr(7 downto 4)=x"8" or instr(7 downto 4)=x"9" else sr when instr(7 downto 4)=x"A" else
		si_i when instr(7 downto 4)=x"B" else si_rev when instr(7 downto 4)=x"C" else
		k when instr(7 downto 4)=x"D" else lreg when instr(7 downto 4)=x"E" else
		dram(to_integer(dp)) when instr(7 downto 4)=x"F" else (others => '0');
	alu_q <= acc(to_integer(unsigned(instr(15 downto 15))));
	alu_p <= x"0001" when instr(19 downto 16)=x"8" or instr(19 downto 16)=x"9" else dram(to_integer(dp)) when instr(21 downto 20)="00" else idb when instr(21 downto 20)="01" else mult_m when instr(21 downto 20)="10" else mult_n;
	mult_m <= std_logic_vector(resize(signed(k)*signed(lreg),31)(30 downto 15));
	mult_n <= std_logic_vector(resize(signed(k)*signed(lreg),31)(14 downto 0)) & '0';
	sr <= rqm & usf1 & usf0 & '0' & dma & drc & "00" & ei & "00000" & p1 & p0;

	process(all) variable c : unsigned(15 downto 0); variable fc : std_logic; begin
		fc := flags(1-to_integer(unsigned(instr(15 downto 15))))(3); c := (others=>'0'); c(0):=fc;
		case instr(19 downto 16) is
			when x"1" => alu_r <= alu_q or alu_p; when x"2" => alu_r <= alu_q and alu_p;
			when x"3" => alu_r <= alu_q xor alu_p; when x"4"|x"8" => alu_r <= std_logic_vector(unsigned(alu_q)-unsigned(alu_p));
			when x"5"|x"9" => alu_r <= std_logic_vector(unsigned(alu_q)+unsigned(alu_p));
			when x"6" => alu_r <= std_logic_vector(unsigned(alu_q)-unsigned(alu_p)-c);
			when x"7" => alu_r <= std_logic_vector(unsigned(alu_q)+unsigned(alu_p)+c);
			when x"A" => alu_r <= not alu_q; when x"B" => alu_r <= alu_q(15)&alu_q(15 downto 1);
			when x"C" => alu_r <= alu_q(14 downto 0)&fc; when x"D" => alu_r <= alu_q(13 downto 0)&"11";
			when x"E" => alu_r <= alu_q(11 downto 0)&"1111"; when x"F" => alu_r <= alu_q(7 downto 0)&alu_q(15 downto 8);
			when others => alu_r <= alu_q;
		end case;
	end process;

	process(clk, reset_n) variable id : std_logic_vector(15 downto 0); variable ai : integer; variable nsp : unsigned(3 downto 0); variable cond : boolean; variable ov, oldov1, olds1, nexts1 : std_logic; variable br : unsigned(8 downto 0); variable target : unsigned(10 downto 0); begin
		if reset_n='0' then
			pc<=(others=>'0'); sp<=(others=>'0'); acc<=(others=>(others=>'0')); flags<=(others=>(others=>'0')); dp<=(others=>'0'); rp<=(others=>'1');
			tr<=(others=>'0'); trb<=(others=>'0'); dr<=(others=>'0'); so<=(others=>'0'); k<=(others=>'0'); lreg<=(others=>'0');
			p0<='0';p1<='0';dma<='0';ei<='0';rqm<='0';drc<='0';usf0<='0';usf1<='0'; irq_phase<=(others=>'0');irq_last<='0';
		elsif rising_edge(clk) then
			irq_last<=int_i; if int_i='1' and irq_last='0' and ei='1' then irq_phase<=to_unsigned(1,2);ei<='0';end if;
			if prog_load_we='1' then pmem(to_integer(unsigned(prog_load_addr)))<=prog_load_data; end if;
			if data_load_we='1' then drom(to_integer(unsigned(data_load_addr)))<=data_load_data; end if;
			if host_dr_we='1' then dr<=host_dr_wdata; rqm<='0'; end if;
			if host_dr_re='1' then rqm<='0'; end if;
			if ce='1' then
				if irq_phase=1 then irq_phase<=to_unsigned(2,2); elsif irq_phase=2 then irq_phase<=(others=>'0'); end if;
				id := idb; if instr(23 downto 22)="11" then id:=instr(21 downto 6); end if;
				if instr(23 downto 22)/="10" then
					case instr(3 downto 0) is
						when x"1"=>acc(0)<=id; when x"2"=>acc(1)<=id; when x"3"=>tr<=id; when x"4"=>dp<=unsigned(id(10 downto 0)); when x"5"=>rp<=unsigned(id(10 downto 0));
						when x"6"=>dr<=id;rqm<='1'; when x"7"=>usf1<=id(14);usf0<=id(13);dma<=id(11);drc<=id(10);ei<=id(7);p1<=id(1);p0<=id(0);
						when x"8"=>for j in 0 to 15 loop so(j)<=id(15-j);end loop; when x"9"=>so<=id; when x"A"=>k<=id; when x"B"=>k<=id;lreg<=drom(to_integer(rp(9 downto 0)));
						when x"C"=>k<=dram(to_integer(dp or to_unsigned(16#40#,11)));lreg<=id; when x"D"=>lreg<=id; when x"E"=>trb<=id; when x"F"=>dram(to_integer(dp))<=id; when others=>null;
					end case;
				end if;
				if instr(23 downto 22)="00" or instr(23 downto 22)="01" then
					if instr(7 downto 4)=x"8" then rqm<='1';end if;
					ai:=to_integer(unsigned(instr(15 downto 15))); if instr(19 downto 16)/=x"0" then
						acc(ai)<=alu_r; flags(ai)(4)<=alu_r(15); if alu_r=x"0000" then flags(ai)(2)<='1'; else flags(ai)(2)<='0'; end if;
						case instr(19 downto 16) is when x"4"|x"6"|x"8"=>if unsigned(alu_r)>unsigned(alu_q) then flags(ai)(3)<='1';else flags(ai)(3)<='0';end if;
							when x"5"|x"7"|x"9"=>if unsigned(alu_r)<unsigned(alu_q) then flags(ai)(3)<='1';else flags(ai)(3)<='0';end if;
							when x"B"=>flags(ai)(3)<=alu_q(0); when x"C"=>flags(ai)(3)<=alu_q(15); when others=>flags(ai)(3)<='0'; end case;
						oldov1:=flags(ai)(1);olds1:=flags(ai)(5);nexts1:=olds1;if oldov1='0' then nexts1:=alu_r(15);end if;ov:=(alu_q(15) xor alu_r(15)) and ((alu_q(15) xor alu_p(15)) xor instr(16)); flags(ai)(0)<=ov;
						if instr(19 downto 16)>=x"4" and instr(19 downto 16)<=x"9" then flags(ai)(1)<=((ov and oldov1) and not(nexts1 xor alu_r(15))) or (ov xor oldov1);flags(ai)(5)<=nexts1;
						elsif instr(19 downto 16)/=x"0" then flags(ai)(0)<='0';flags(ai)(1)<='0';if oldov1='0' then flags(ai)(5)<=alu_r(15);end if;end if;
					end if;
					if instr(3 downto 0)/=x"4" then case instr(14 downto 13) is when "01"=>dp(3 downto 0)<=dp(3 downto 0)+1;when "10"=>dp(3 downto 0)<=dp(3 downto 0)-1;when "11"=>dp(3 downto 0)<=(others=>'0');when others=>null;end case;dp(7 downto 4)<=dp(7 downto 4) xor unsigned(instr(12 downto 9));end if;
					if instr(8)='1' and instr(3 downto 0)/=x"5" then rp<=rp-1; end if;
				end if;
				if irq_phase=1 then pc<=pc;
				elsif instr(23 downto 22)="01" then nsp:=sp-1;pc<=stack(to_integer(nsp));sp<=nsp;
				elsif instr(23 downto 22)="10" then
					br:=unsigned(instr(21 downto 13));target:=unsigned(instr(12 downto 2));cond:=false;
					case to_integer(br) is
						when 16#000#=>pc<=unsigned(so(10 downto 0));
						when 16#080#|16#082#=>cond:=(flags(0)(3)=br(1));when 16#084#|16#086#=>cond:=(flags(1)(3)=br(1));
						when 16#088#|16#08A#=>cond:=(flags(0)(2)=br(1));when 16#08C#|16#08E#=>cond:=(flags(1)(2)=br(1));
						when 16#090#|16#092#=>cond:=(flags(0)(0)=br(1));when 16#094#|16#096#=>cond:=(flags(1)(0)=br(1));
						when 16#098#|16#09A#=>cond:=(flags(0)(1)=br(1));when 16#09C#|16#09E#=>cond:=(flags(1)(1)=br(1));
						when 16#0A0#|16#0A2#=>cond:=(flags(0)(4)=br(1));when 16#0A4#|16#0A6#=>cond:=(flags(1)(4)=br(1));
						when 16#0A8#|16#0AA#=>cond:=(flags(0)(5)=br(1));when 16#0AC#|16#0AE#=>cond:=(flags(1)(5)=br(1));
						when 16#0B0#=>cond:=(dp(3 downto 0)=0);when 16#0B1#=>cond:=(dp(3 downto 0)/=0);when 16#0B2#=>cond:=(dp(3 downto 0)=15);when 16#0B3#=>cond:=(dp(3 downto 0)/=15);
						when 16#0B4#|16#0B6#=>cond:=(siack_i=br(1));when 16#0B8#|16#0BA#=>cond:=(soack_i=br(1));
						when 16#0BC#=>cond:=(rqm='0');when 16#0BE#=>cond:=(rqm='1');
						when 16#100#|16#101#=>pc<=target;when 16#140#|16#141#=>if irq_phase=2 then stack(to_integer(sp))<=pc;else stack(to_integer(sp))<=pc+1;end if;sp<=sp+1;pc<=target;
						when others=>null;
					end case;
					if br>=16#080# and br<=16#0BE# then if cond then pc<=target;else pc<=pc+1;end if;end if;
				else pc<=pc+1; end if;
			end if;
		end if;
	end process;

	host_dr_rdata<=dr; p0_o<=p0;p1_o<=p1;dma_o<=dma;ei_o<=ei;rqm_o<=rqm;dbg_pc<=std_logic_vector(pc);dbg_ir<=instr;
	dbg_acca<=acc(0);dbg_accb<=acc(1);dbg_dp<="00000"&std_logic_vector(dp);dbg_rp<="00000"&std_logic_vector(rp);dbg_dr<=dr;dbg_sr<=sr;dbg_flaga<=flags(0);dbg_flagb<=flags(1);dbg_sp<=std_logic_vector(sp);
end architecture;
