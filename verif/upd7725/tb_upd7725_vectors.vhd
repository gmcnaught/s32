library ieee;use ieee.std_logic_1164.all;use ieee.numeric_std.all;use std.textio.all;use ieee.std_logic_textio.all;
entity tb_upd7725_vectors is generic(VECTOR_FILE:string;BRANCH_FILE:string);end;
architecture t of tb_upd7725_vectors is
 signal clk:std_logic:='0';signal ce,rst,we:std_logic:='0';signal pa,pc:std_logic_vector(10 downto 0):=(others=>'0');signal pd,ir:std_logic_vector(23 downto 0):=(others=>'0');
 signal aa,ab,dp,rp,dr,sr,hr:std_logic_vector(15 downto 0);signal fa,fb:std_logic_vector(5 downto 0);signal sp:std_logic_vector(3 downto 0);signal p0,p1,dma,ei,rqm:std_logic;
begin clk<=not clk after 5 ns;
 d:entity work.upd7725_lab port map(clk=>clk,ce=>ce,reset_n=>rst,prog_load_we=>we,prog_load_addr=>pa,prog_load_data=>pd,host_dr_rdata=>hr,p0_o=>p0,p1_o=>p1,dma_o=>dma,ei_o=>ei,rqm_o=>rqm,dbg_pc=>pc,dbg_ir=>ir,dbg_acca=>aa,dbg_accb=>ab,dbg_dp=>dp,dbg_rp=>rp,dbg_dr=>dr,dbg_sr=>sr,dbg_flaga=>fa,dbg_flagb=>fb,dbg_sp=>sp);
 process file f:text open read_mode is VECTOR_FILE;file bf:text open read_mode is BRANCH_FILE;variable l:line;variable o0,o1,o2:std_logic_vector(23 downto 0);variable ea,eb:std_logic_vector(15 downto 0);variable efa,efb:std_logic_vector(7 downto 0);variable epc:std_logic_vector(11 downto 0);variable n:natural:=0;
 begin while not endfile(f) loop readline(f,l);hread(l,o0);hread(l,o1);hread(l,o2);hread(l,ea);hread(l,eb);hread(l,efa);hread(l,efb);
  rst<='1';ce<='0';for i in 0 to 2 loop pa<=std_logic_vector(to_unsigned(i,11));if i=0 then pd<=o0;elsif i=1 then pd<=o1;else pd<=o2;end if;we<='1';wait until rising_edge(clk);end loop;we<='0';rst<='0';wait until rising_edge(clk);rst<='1';ce<='1';for i in 0 to 2 loop wait until rising_edge(clk);wait for 1 ns;end loop;ce<='0';
  assert aa=ea and ab=eb and fa=efa(5 downto 0) and fb=efb(5 downto 0) report "vector mismatch "&integer'image(n) severity failure;n:=n+1;
 end loop;
 while not endfile(bf) loop readline(bf,l);hread(l,o0);hread(l,epc);rst<='1';ce<='0';pa<=(others=>'0');pd<=o0;we<='1';wait until rising_edge(clk);we<='0';rst<='0';wait until rising_edge(clk);rst<='1';ce<='1';wait until rising_edge(clk);wait for 1 ns;ce<='0';assert pc=epc(10 downto 0) report "branch vector mismatch "&integer'image(n) severity failure;n:=n+1;end loop;
 report "PASS 30 ALU and 34 branch MAME-model vectors" severity note;std.env.stop;end process;
end;
