library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;
entity loopback is
PORT(
		clk_in : IN STD_LOGIC;
		
		-- control
		reset_l : IN STD_LOGIC;
		
		rxf_l : IN STD_LOGIC;
		txe_l : IN STD_LOGIC;
		oe_l : OUT STD_LOGIC;
		rd_l : OUT STD_LOGIC;
		wr_l : OUT STD_LOGIC;
		siwua : OUT STD_LOGIC;
		wdi: OUT STD_LOGIC;
		data : INOUT STD_LOGIC_VECTOR(7 downto 0);
		---  vga
		
		h_sync : OUT STD_LOGIC;
		v_sync : OUT STD_LOGIC;
		r0 : OUT STD_LOGIC;
		r1 : OUT STD_LOGIC;
		r2 : OUT STD_LOGIC;
		g0 : OUT STD_LOGIC;
		g1 : OUT STD_LOGIC;
		g2 : OUT STD_LOGIC;
		b0 : OUT STD_LOGIC;
		b1 : OUT STD_LOGIC;
		b2 : OUT STD_LOGIC
		
	);
end loopback;

architecture Behavioral of loopback is
	
	COMPONENT myram
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    clkb : IN STD_LOGIC;
    rstb : IN STD_LOGIC;
    addrb : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );
END COMPONENT;

	component mydcm is
port
 (-- Clock in ports
  CLK_IN1           : in     std_logic;
  -- Clock out ports
  CLK_OUT1          : out    std_logic;
  CLK_OUT2          : out    std_logic
 );
end component;

	--States
	TYPE states IS (
	s0,--Reset State.  Set addr_counter to 0
	s1,--Wait State. Do nothing while rxf = 1
	s2,--Prepare for read. Next clock oe
	s3,--Oe is out for the first time. no data till next tick
	s4,--Data 0 is out. Read it into the upper byte. Assert rd next tick
	s5,--Data 0 should be in upper byte. Set bc to 1. Rd should be down
	s6,--Data 1 is out. Read into upper byte. 
	s7,--Data 2 is out. Read into upper byte. set mem
	s8,--There is a byte in upper byte. next clock asser oe
	s9,--Oe currently asserted next byte should be out next tick
	s10, -- Data 1 is out read it into upper byte. Drop read
	s11, -- Data 1 is in upper byte. Read down.
	s12, -- Data 2 is out. Read it in
	s13 -- Data 3 is out. Read in
	);
	
	SIGNAL state: states := s0;
	SIGNAL nxt_state : states := s0;
	
	--Clks
	SIGNAL d_clk : STD_LOGIC := '0';
	SIGNAL v_clk : STD_LOGIC := '0';
	
		--read byte
	SIGNAL en_lower: STD_LOGIC:= '0';
	SIGNAL d_lower : STD_LOGIC_VECTOR(7 downto 0):= (others => '0');
	SIGNAL en_upper: STD_LOGIC:= '0';
	SIGNAL d_upper : STD_LOGIC_VECTOR(7 downto 0):= (others => '0');
		--Write To Memory
	SIGNAL d_in : STD_LOGIC_VECTOR(8 downto 0);
	SIGNAL byte_counter : STD_LOGIC:= '0';
	SIGNAL nxt_byte_counter : STD_LOGIC:= '0';
	--Control
	SIGNAL concat : STD_LOGIC_VECTOR(15 downto 0);
	SIGNAL crap : STD_LOGIC; -- all ones
		--Read Control
	SIGNAL nxt_oe_l : STD_LOGIC;
	SIGNAL nxt_rd_l : STD_LOGIC;
	SIGNAL tmp_oe_l : STD_LOGIC := '1';
	SIGNAL tmp_rd_l : STD_LOGIC := '1';
	
	--Memory control
	SIGNAL mem_set : STD_LOGIC_VECTOR(0 downto 0) := (others => '0'); --memory should be set the next tick
	SIGNAL mem_full : STD_LOGIC := '0';
	SIGNAL d_addr_counter : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
	SIGNAL v_addr_counter : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
		--Watchdog
	SIGNAL watch_dog_counter: STD_LOGIC_VECTOR(1 downto 0) := (others => '0');
		--Video
	SIGNAL d_out : STD_LOGIC_VECTOR(8 downto 0):=(others => '0');
		--RGB To Display start as white
	SIGNAL rgb : STD_LOGIC_VECTOR(8 downto 0) := (others => '1');
		--Video Counters
	SIGNAL h_counter : STD_LOGIC_VECTOR(9 downto 0) := "0000000000";
	SIGNAL v_counter : STD_LOGIC_VECTOR(9 downto 0) := "0000000000";
		--Next h_sync
	SIGNAL tmp_h_sync: STD_LOGIC := '1';
	SIGNAL tmp_v_sync: STD_LOGIC := '1';
		--Reset
	SIGNAL d_reset_meta_l: STD_LOGIC := '0';
	SIGNAL d_reset_sync_l: STD_LOGIC := '0';
		--Reset
	SIGNAL v_reset_meta_l: STD_LOGIC := '0';
	SIGNAL v_reset_sync_l: STD_LOGIC := '0';
		--video counter resets
	SIGNAL h_counter_reset : STD_LOGIC;
	SIGNAL v_counter_reset : STD_LOGIC;
	
	--Enable Color
	SIGNAL color_en: STD_LOGIC;
		--Temporary Sync Signals
	SIGNAL nxt_h_sync: STD_LOGIC;
	SIGNAL nxt_v_sync: STD_LOGIC;
		--Next ADDRESS of color to get
	SIGNAL nxt_v_addr_counter: STD_LOGIC_VECTOR(15 downto 0);
	
		--Fliped reset
	SIGNAL v_reset_h : STD_LOGIC;
			
begin

clkControl : mydcm
		port map
   (-- Clock in ports
    CLK_IN1 => clk_in,
    -- Clock out ports
    CLK_OUT1 => d_clk,
    CLK_OUT2 => v_clk);

memory : myram
  PORT MAP (
    clka => d_clk,
    wea => mem_set,
    addra => d_addr_counter,
    dina => d_in,
    clkb => v_clk,
    rstb => v_reset_h,
    addrb => v_addr_counter,
    doutb => d_out
  );
	
	--D Reset
	d_reset_m : PROCESS (d_clk)
	BEGIN
		if (rising_edge(d_clk)) then
			d_reset_meta_l <= reset_l;
		end if;
	
	END PROCESS d_reset_m;
	
	--D Reset
	d_reset_s : PROCESS (d_clk)
	BEGIN
		if (rising_edge(d_clk)) then
			d_reset_sync_l <= d_reset_meta_l;
		end if;
	
	END PROCESS d_reset_s;
	
	
	--V Reset
	v_reset_m : PROCESS (v_clk)	
	BEGIN
	if  (rising_edge(v_clk)) then
			v_reset_meta_l <= d_reset_sync_l;
		end if;
	END PROCESS v_reset_m;
	
	--V Reset
	v_reset_s : PROCESS (v_clk)	
	BEGIN
	if  (rising_edge(v_clk)) then
			v_reset_sync_l <= v_reset_meta_l;
		end if;
	END PROCESS v_reset_s;
	
	--Actual State Transactions
	set_state : PROCESS (d_clk)
	BEGIN
		--Handle states
		if (rising_edge(d_clk)) then
		
			if((crap='1') or d_reset_sync_l='0') then
				state <= s0;
			elsif (rxf_l = '1') then
				state <= s1;
			else
				state <= nxt_state;
			end if;
			
		end if;
		
	END PROCESS set_state;
	
	watch : PROCESS (d_clk)
	BEGIN
		if (rising_edge(d_clk)) then
		--Watchdog
			if(state = s0 or state = s1 or state = s2 or state = s3 or state = s4 or state = s5 or state = s6 or state = s7 or state = s8 or state = s9 or state = s10 or state = s11 or state = s12 or state = s13) then
				watch_dog_counter <= watch_dog_counter +1;
			else
				watch_dog_counter <= (others => '0');
			end if;
		end if;
	END PROCESS watch;
	
	read_data_lower : PROCESS (d_clk)
	BEGIN
		if (rising_edge(d_clk)) then
			--Lower Byte Read
			if state = s0 then
				d_lower <= (others => '0');
			elsif en_lower = '1' then
				d_lower <= d_upper;
			end if;
		end if;
	END PROCESS read_data_lower;
	
	read_data_upper : PROCESS (d_clk)
	BEGIN
		if (rising_edge(d_clk)) then
			--Upper byte Read
			if state = s0 then
				d_upper <= (others => '0');
			elsif en_upper = '1' then
				d_upper <= data;
			end if;
		end if;
	END PROCESS read_data_upper;
	
	count_bytes : PROCESS (d_clk)
	BEGIN
		--Byte Counter
		if (rising_edge(d_clk)) then
			if rxf_l = '0' then
				byte_counter <= nxt_byte_counter;
			end if;
		end if;			
	END PROCESS count_bytes;
	
	--Handle register transfers for v clock.
	v_clkd : PROCESS (v_clk)
	BEGIN
		--Handle Counters
		if (rising_edge(v_clk)) then
			---799
			if h_counter_reset = '1' then
				h_counter <= ( others => '0');
			else
				h_counter <= h_counter+1;
			end if;
			
			--524
			if v_counter_reset = '1' then
				v_counter <= ( others => '0');
			elsif h_counter_reset = '1' then
				v_counter <= v_counter+1;
			end if;
		end if;
		
	END PROCESS v_clkd;
	
	--Pick the color to use
	pick_color: PROCESS (v_clk)
	BEGIN
		if (rising_edge(v_clk)) then
			if color_en = '0' then
				rgb <= (others => '0');
			else
				rgb <= d_out;
			end if;
		end if;
	END PROCESS pick_color;
	
	--GEN SYNC SIGNALS
	sync : PROCESS (v_clk)
	BEGIN
		if(rising_edge(v_clk)) then
			tmp_h_sync <= nxt_h_sync;
			tmp_v_sync <= nxt_v_sync;
		end if;
	END PROCESS sync;
	
	
	--Handle Data Address Calculation
	d_addr_gen : PROCESS(d_clk)
	BEGIN
		if (rising_edge(d_clk)) then
			if (state = s0) then
				d_addr_counter <= ( others => '0');
			else
				if (mem_set = "1" and mem_full = '0') then
					d_addr_counter <= d_addr_counter + 1;
				end if;
			end if;
		end if;
	END PROCESS d_addr_gen;
	
	--Handle state transitions
	state_trans: PROCESS(rxf_l, txe_l, state, byte_counter)
	BEGIN
			CASE state IS
				when s0 => nxt_state <= s1;
				when s1 => if (byte_counter = '0') then
									nxt_state <= s2;
								else
									nxt_state <= s8;
								end if;
				when s2 => nxt_state <= s3;
				when s3 => nxt_state <= s4;
				when s4 => nxt_state <= s5;
				when s5 => nxt_state <= s6;
				when s6 => nxt_state <= s7;
				when s7 => nxt_state <= s6;
				----Already read byte
				when s8 => nxt_state <= s9;
				when s9 => nxt_state <= s10;
				when s10 => nxt_state <= s11;
				when s11 => nxt_state <= s12;
				when s12 => nxt_state <= s13;
				when s13 => nxt_state <= s12;
				
			END CASE;
	END PROCESS state_trans;
	
	--Handle CL to Register  transfers
	d_output: PROCESS(d_clk)
	BEGIN
	
		if(rising_edge(d_clk)) then
			tmp_oe_l <= nxt_oe_l;
			tmp_rd_l <= nxt_rd_l;
		end if;	
		
	END PROCESS d_output;
	
	--Get DATA FROM Memory 
	color_data: PROCESS(v_clk)
	BEGIN
		if(rising_edge(v_clk)) then
			v_addr_counter <= nxt_v_addr_counter;
		end if;
	END PROCESS color_data;
	
	oe_l <= tmp_oe_l or rxf_l;
	rd_l <= tmp_rd_l or rxf_l;
	
	--Read  FTDI Logic
	nxt_oe_l <= '0' when ((state = s2 or state = s3 or state = s4 or state = s5 or state = s6 or state = s7 or state = s8 or state = s9 or state = s10 or state = s11 or state = s12 or state = s13) and rxf_l= '0') else '1';
	nxt_rd_l <= '0' when ((state = s4 or state = s5 or state = s6 or state = s7 or state = s10 or state = s11 or state = s12 or state = s13) and rxf_l= '0') else '1';
	en_upper <= '1' when ((state = s4 or state = s6 or state = s7 or state = s10 or state = s12 or state = s13) and rxf_l= '0') else '0';
	en_lower <= '1' when ((state = s6 or state = s10 or state = s13 ) and rxf_l= '0') else '0';
	nxt_byte_counter <= '0' when ((state = s0 or state = s6 or state = s10 or state = s13) and rxf_l='0') else '1' when ((state = s4 or state = s7 or state = s12) and rxf_l='0') else byte_counter;
	--Write MEM Logic
	concat <= d_upper & d_lower;
	crap <= '1' when not (d_upper & d_lower) = 0 else '0';
	d_in <= concat(8 downto 0);
	mem_full <= '1' when not (d_addr_counter) = 0 else '0';
	mem_set <= (others => '1') when ((state = s7 or state = s12 )) else (others => '0');
	
	--RESET HCOUNTER
	h_counter_reset <= '1' when (h_counter = 799) else '0';
	v_counter_reset <= '1' when (v_counter = 524) else '0';
	--GEN ADDRESS to get color before color enable
	nxt_v_addr_counter <= (v_counter(7 downto 0) + (256-45)) & (h_counter(7 downto 0) + (256-157));
	--enable color the tick before data comes out. 
	color_en <= '1' WHEN ((159 <= h_counter) and (h_counter < 800) and (44 < v_counter) and (v_counter < 525)) else '0';
	--sync
	nxt_h_sync <= '0' when (0 <= h_counter and h_counter < 96) else '1';
	nxt_v_sync <= '0' when (0 <= v_counter and v_counter < 2) else '1';
	h_sync <= tmp_h_sync;
	v_sync <= tmp_v_sync;
	--color 
	r2 <= rgb(8);
	r1 <= rgb(7);
	r0 <= rgb(6);
	g2 <= rgb(5);
	g1 <= rgb(4);
	g0 <= rgb(3);
	b2 <= rgb(2);
	b1 <= rgb(1);
	b0 <= rgb(0);
	-- Drive Watch Dog
	wdi <= '1' when not (watch_dog_counter) = 0 else '0';
	--Currently Undriven signals
	siwua <= '1';
	wr_l <= '1';
	
	--Handle reset
	v_reset_h <= not v_reset_sync_l;
	
end Behavioral;

