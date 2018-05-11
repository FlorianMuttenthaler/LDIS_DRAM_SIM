-------------------------------------------------------------------------------
--
-- Memory Interface
--
-------------------------------------------------------------------------------
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ram2ddrxadc_pkg.all;
use work.fifo_buffer_pkg.all;

--
-------------------------------------------------------------------------------
--
entity memory is

	-- 'ENABLE_16_BIT', 'FIFO_DEPTH_WRITE' and 'FIFO_DEPTH_READ' is the generic value of the entity.
	-- 'clk_200MHz', 'rst', 'address', 'data_in' and 'r_w' are the inputs of entity.
	-- 'mem_ready' and 'data_out' are the outputs of the entity.

	generic(
		ENABLE_16_BIT					: integer range 0 to 1 := 0; -- Default: 0 = disabled, 1 = enabled
		-- Size of FIFO buffers
		FIFO_DEPTH_WRITE				: integer := 8; -- Default: 8
		FIFO_DEPTH_READ  				: integer := 8  -- Default: 8	
	);
		
	port (
    	clk_200MHz      				: in  std_logic; -- 200 MHz system clock => 5 ns period time
		rst             				: in  std_logic; -- active high system reset
		address 	     				: in  std_logic_vector(26 downto 0); -- address space
		data_in          				: in  std_logic_vector((8 * (1 + ENABLE_16_BIT) - 1) downto 0); -- data byte input
		r_w			     				: in  std_logic; -- Read or Write flag: '1' ... write, '0' ... read
		mem_ready						: out std_logic; -- allocated memory ready or busy flag: '1' ... ready, '0' ... busy
		data_out         				: out std_logic_vector((8 * (1 + ENABLE_16_BIT) - 1) downto 0) -- data byte output
	);

end memory;
--
--------------------------------------------------------------------------------
--
architecture beh of memory is
	-- Signals of ram2ddrxadc
	signal device_temp_i 			: std_logic_vector(11 downto 0) := (others => '0');
    
	-- RAM interface
   	signal ram_a 						: std_logic_vector(26 downto 0) := (others => '0');
   	signal ram_dq_i					: std_logic_vector(15 downto 0) := (others => '0');
	signal ram_dq_o					: std_logic_vector(15 downto 0);
   	signal ram_cen						: std_logic := '1';
	signal ram_oen						: std_logic := '1';
	signal ram_wen						: std_logic := '1';
	signal ram_ub 						: std_logic := '0';
	signal ram_lb 						: std_logic := '1';

--	-- Idle: cen, oen, wen = '1'
--	-- Read: cen, oen, lb, ub = '0' and wen = '1'
--	-- Write: cen, wen, lb, ub = '0' and oen = '1'
  
	-- DDR2 interface
	signal ddr2_addr 					: std_logic_vector(12 downto 0);
   	signal ddr2_ba 	 				: std_logic_vector(2 downto 0);
	signal ddr2_ras_n					: std_logic;
	signal ddr2_cas_n					: std_logic;
	signal ddr2_we_n					: std_logic;
	signal ddr2_ck_p					: std_logic_vector(0 downto 0);
	signal ddr2_ck_n					: std_logic_vector(0 downto 0);
	signal ddr2_cke					: std_logic_vector(0 downto 0);
	signal ddr2_cs_n					: std_logic_vector(0 downto 0);
	signal ddr2_odt					: std_logic_vector(0 downto 0);
	signal ddr2_dm						: std_logic_vector(1 downto 0);
	signal ddr2_dqs_p					: std_logic_vector(1 downto 0);
	signal ddr2_dqs_n					: std_logic_vector(1 downto 0);
	signal ddr2_dq 					: std_logic_vector(15 downto 0);
	
	--Copies of address and data input
	signal address_cpy				: std_logic_vector(26 downto 0);
	signal address_cpy_read			: std_logic_vector(26 downto 0);
	signal data_cpy					: std_logic_vector((8 * (1 + ENABLE_16_BIT) - 1) downto 0);
		
	-- FIFOs
	-- the instanziated FIFOs are based on the designed entity of robin-arbaud
	constant DATA_BASE_WIDTH_DATA	: integer := 8 * (1 + ENABLE_16_BIT); -- storage unit length
	constant DATA_BASE_WIDTH_ADDR : integer := 27; -- storage unit length
	constant DATA_IN_WIDTH			: integer := 1;  -- number of units stored on write
	constant DATA_OUT_WIDTH			: integer := 1;  -- number of units loaded on read

	-- dataIn signals
	signal dataIn_write_data 		: std_logic_vector((DATA_IN_WIDTH * DATA_BASE_WIDTH_DATA -1) downto 0);
	signal dataIn_read_data 		: std_logic_vector((DATA_IN_WIDTH * DATA_BASE_WIDTH_DATA -1) downto 0);
	signal dataIn_write_add 		: std_logic_vector((DATA_IN_WIDTH * DATA_BASE_WIDTH_ADDR -1) downto 0);
	signal dataIn_read_add 			: std_logic_vector((DATA_IN_WIDTH * DATA_BASE_WIDTH_ADDR -1) downto 0);
	
	-- write signals
	signal write_dataIn 				: std_logic := '0';
	signal write_dataOut_data		: std_logic := '0';
	signal write_dataOut_add		: std_logic := '0';
	
	-- read signals
	signal read_dataIn 				: std_logic := '0';
	signal read_dataOut_data		: std_logic := '0';
	signal read_dataOut_add			: std_logic := '0';
	
	-- empty flags
	signal empty_write_data			: std_logic;
	signal empty_write_add			: std_logic;
	signal empty_read_data			: std_logic;
	signal empty_read_add			: std_logic;
	
	-- full flags
	signal full_write_data			: std_logic;
	signal full_write_add			: std_logic;
	signal full_read_data			: std_logic;
	signal full_read_add				: std_logic;
	
	-- dataOut signals
	signal dataOut_write_data 		: std_logic_vector((DATA_IN_WIDTH * DATA_BASE_WIDTH_DATA -1) downto 0);
	signal dataOut_read_data 		: std_logic_vector((DATA_IN_WIDTH * DATA_BASE_WIDTH_DATA -1) downto 0);
	signal dataOut_write_add		: std_logic_vector((DATA_IN_WIDTH * DATA_BASE_WIDTH_ADDR -1) downto 0);
	signal dataOut_read_add 		: std_logic_vector((DATA_IN_WIDTH * DATA_BASE_WIDTH_ADDR -1) downto 0);

	--Internal Counter
	constant COUNTER_MAX_WRITE		: integer := 54; -- for 260ns cycle
	constant COUNTER_MAX_READ		: integer := 120; -- for 350ns cycle
	signal start_counter				: std_logic := '0';
--	signal counter_write				: integer := 0;
--	signal counter_read				: integer := 0;
    signal counter				: integer := 0;
	signal cnt_write					: std_logic := '0';
	signal cnt_read					: std_logic := '0';
	
	-- States:
	type type_state is (
		STATE_IDLE,
		STATE_RAM_WRITE_FIFO,
		STATE_RAM_WRITE,
		STATE_WRITE_WAIT,
		STATE_RAM_READ_FIFO,
		STATE_RAM_READ,
		STATE_READ_WAIT
	);

	signal state, state_next : type_state := STATE_IDLE;
	
begin
	
	ram2ddrxadc: entity work.ram2ddrxadc
		port map (
			-- Common
			clk_200MHz_i		=> clk_200MHz,
			rst_i 				=> rst,
			device_temp_i 		=> device_temp_i,
	
			-- RAM interface
			ram_a 				=> ram_a,
			ram_dq_i 			=> ram_dq_i,
			ram_dq_o 			=> ram_dq_o,
			ram_cen 			=> ram_cen,
			ram_oen 			=> ram_oen,
			ram_wen 			=> ram_wen,
			ram_ub 				=> ram_ub,
			ram_lb 				=> ram_lb,
	
			-- DDR2 interface
			ddr2_addr 			=> ddr2_addr,
			ddr2_ba 			=> ddr2_ba,
			ddr2_ras_n 			=> ddr2_ras_n,
			ddr2_cas_n 			=> ddr2_cas_n,
			ddr2_we_n 			=> ddr2_we_n,
			ddr2_ck_p 			=> ddr2_ck_p,
			ddr2_ck_n 			=> ddr2_ck_n,
			ddr2_cke 			=> ddr2_cke,
			ddr2_cs_n 			=> ddr2_cs_n,
			ddr2_dm 			=> ddr2_dm,
			ddr2_odt 			=> ddr2_odt,
			ddr2_dq 			=> ddr2_dq,
			ddr2_dqs_p 			=> ddr2_dqs_p,
			ddr2_dqs_n 			=> ddr2_dqs_n
		);
		
	-- FIFO for addresses, write operation
	fifo_buffer_addr_write: entity work.fifo_buffer
		generic map(
			DATA_BASE_WIDTH	=> DATA_BASE_WIDTH_ADDR,
			DATA_IN_WIDTH 	=> DATA_IN_WIDTH,
			DATA_OUT_WIDTH 	=> DATA_OUT_WIDTH,
			FIFO_DEPTH 		=> FIFO_DEPTH_WRITE
		)
			
		port map(
			clk 			=> clk_200MHz,
			rst 			=> rst,
			write 			=> write_dataIn,
			dataIn 			=> address,
			read 			=> read_dataIn,
			dataOut 		=> dataOut_write_add,
			empty 			=> empty_write_add,
			full 			=> full_write_add
		);
	
	-- FIFO for addresses, read operation
	fifo_buffer_addr_read: entity work.fifo_buffer
		generic map(
			DATA_BASE_WIDTH => DATA_BASE_WIDTH_ADDR,
			DATA_IN_WIDTH 	=> DATA_IN_WIDTH,
			DATA_OUT_WIDTH 	=> DATA_OUT_WIDTH,
			FIFO_DEPTH 		=> FIFO_DEPTH_READ
		)
			
		port map(
			clk 			=> clk_200MHz,
			rst 			=> rst,
			write 			=> write_dataOut_add,
			dataIn 			=> address,
			read 			=> read_dataOut_add,
			dataOut 		=> dataOut_read_add,
			empty 			=> empty_read_add,
			full 			=> full_read_add
		);
		
	-- FIFO for data, write operation
	fifo_buffer_data_write: entity work.fifo_buffer
		generic map(
			DATA_BASE_WIDTH => DATA_BASE_WIDTH_DATA,
			DATA_IN_WIDTH 	=> DATA_IN_WIDTH,
			DATA_OUT_WIDTH 	=> DATA_OUT_WIDTH,
			FIFO_DEPTH 		=> FIFO_DEPTH_WRITE
		)
			
		port map(
			clk 			=> clk_200MHz,
			rst 			=> rst,
			write 			=> write_dataIn,
			dataIn 			=> data_in,
			read 			=> read_dataIn,
			dataOut 		=> dataOut_write_data,
			empty 			=> empty_write_data,
			full 			=> full_write_data
		);
		
	-- FIFO for data, read operation
	fifo_buffer_data_read: entity work.fifo_buffer
		generic map(
			DATA_BASE_WIDTH => DATA_BASE_WIDTH_DATA,
			DATA_IN_WIDTH 	=> DATA_IN_WIDTH,
			DATA_OUT_WIDTH	=> DATA_OUT_WIDTH,
			FIFO_DEPTH 		=> FIFO_DEPTH_READ
		)
			
		port map(
			clk 			=> clk_200MHz,
			rst 			=> rst,
			write 			=> write_dataOut_data,
			dataIn 			=> dataIn_read_data,
			read 			=> read_dataOut_data,
			dataOut 		=> dataOut_read_data,
			empty 			=> empty_read_data,
			full 			=> full_read_data
		);

-------------------------------------------------------------------------------
-- Selection related to the size of the data bytes for handling the ram2ddrxadc module
--
	ram_lb <= '0' when ENABLE_16_BIT = 1 else '1';
		
-------------------------------------------------------------------------------
--
-- Process sync_proc_fifos: triggered by clk_200MHz, r_w, full_write_data, full_write_add, full_read_add, empty_read_data, 
--		address_cpy, address, data_cpy, data_in, address_cpy_read, dataOut_read_data
-- Main sync process for fifo management
--
	sync_proc_fifos: process (clk_200MHz, r_w, full_write_data, full_write_add, full_read_add, empty_read_data, 
							  address_cpy, address, data_cpy, data_in, address_cpy_read, dataOut_read_data)
	begin
		if rising_edge(clk_200MHz) then
			if r_w = '1' then -- write
				if (full_write_data = '0' and full_write_add = '0' and (address_cpy /= address or data_cpy /= data_in)) then
					write_dataIn <= '1'; -- writes address and data to FIFO
					--dataIn_write_data <= data_in;
					--dataIn_write_add <= address;
					--Copies
					data_cpy <= data_in;
					address_cpy <= address;
				else
					write_dataIn <= '0'; -- disable write for FIFO
				end if;
			else -- read
				if full_read_add = '0' and address_cpy_read /= address then
					write_dataOut_add <= '1'; -- writes address to FIFO
					--dataIn_read_add <= address;
					--Copies
					address_cpy_read <= address;
				else
					write_dataOut_add <= '0'; -- disable write for FIFO
				end if;
				if empty_read_data = '0' then
					read_dataOut_data <= '1'; -- reads data from FIFO
					data_out <= dataOut_read_data;
				else
					read_dataOut_data <= '0'; -- disable read for FIFO
				end if;
			end if;
		end if;		
	end process sync_proc_fifos;
	
-------------------------------------------------------------------------------
--
-- Process counter_proc: triggered by clk_200MHz, counter, rst, start_counter
-- implemtation for counter
--
	counter_proc: process (clk_200MHz, counter, rst, start_counter)
--	counter_proc: process (clk_200MHz, counter_write, counter_read, r_w, rst, start_counter)
	begin
		if rst = '1' then -- Reset Counter and signals
			counter <= 0;
			cnt_write <= '0';	
			cnt_read <= '0'; 
			--counter_write <= 0;
			--counter_read <= 0;
		elsif start_counter = '1' then		
			if rising_edge(clk_200MHz) then
--				if r_w = '1' then
--					if counter_write = 0 then
--						cnt_write <= '0';
--					end if;
--					if counter_write = COUNTER_MAX_WRITE then -- 260ns
--						counter_write <= 0;
--						cnt_write <= '1';
--					else
--						counter_write <= counter_write + 1;
--					end if;
--					counter_read <= 0;
--				else
--					if counter_read = 0 then
--						cnt_read <= '0';
--					end if;
--					if counter_write = COUNTER_MAX_READ then -- 260ns
--						counter_read <= 0;
--						cnt_read <= '1';
--					else
--						counter_read <= counter_read + 1;
--					end if;
--					counter_write <= 0;					
--				end if;
				
				if counter = 0 then
					cnt_write <= '0';	-- Clear signals
					cnt_read <= '0'; 
				end if;
				
				if counter = COUNTER_MAX_READ then -- 210ns
					cnt_read <= '1'; 
					counter <= 0;
				elsif counter = COUNTER_MAX_WRITE then -- 260ns
					cnt_write <= '1';	
					counter <= counter + 1;					
				else
					counter <= counter + 1;
				end if;
			end if;
		end if;
	end process counter_proc;
		
-------------------------------------------------------------------------------
--
-- Process sync_proc_state: triggered by clk_200MHz, rst
-- if reset active, resets state maschine and signals
-- each clk period states and flags are updated
--
	sync_proc_state: process (clk_200MHz, rst)
	begin
		if rst = '1' then -- Reset
			state <= STATE_IDLE;
			
		elsif rising_edge(clk_200MHz) then
			state <= state_next;
		end if;
	end process sync_proc_state;
				
-------------------------------------------------------------------------------
--
-- Process sync_proc_ram: triggered by state, r_w, empty_write_data, empty_write_add, empty_read_add, full_read_data, 
--			dataOut_write_add, dataOut_write_data, dataOut_read_add, ram_dq_o
-- Main sync process for ram mangement
--
	sync_proc_ram: process (state, r_w, empty_write_data, empty_write_add, empty_read_add, full_read_data, 
							dataOut_write_add, dataOut_write_data, dataOut_read_add, ram_dq_o, cnt_write, cnt_read)
	begin
	
		case state is
		
			when STATE_IDLE =>
				-- stop counter
				start_counter <= '0';
			
				-- reset control signals
				ram_cen <= '1'; 
				ram_oen <= '1';
				ram_wen <= '1';
			
				if r_w = '1' then
					state_next <= STATE_RAM_WRITE_FIFO;
				elsif r_w = '0' then
					state_next <= STATE_RAM_READ_FIFO;
				else
				    null;
				end if;
				
			when STATE_RAM_WRITE_FIFO =>
			
			    if empty_write_data = '0' and empty_write_add = '0' then
                    read_dataIn <= '1'; -- reads address and data from FIFO
                    state_next <= STATE_RAM_WRITE; 
                else
                    read_dataIn <= '0'; -- disable read for FIFO
                    state_next <= STATE_IDLE; 
                end if;
                
			when STATE_RAM_WRITE =>
			
				-- set control signals
				ram_cen <= '0'; 
				ram_oen <= '1';
				ram_wen <= '0';
				
				ram_a <= dataOut_write_add;
					
                if ENABLE_16_BIT = 1 then
                    ram_dq_i <= dataOut_write_data; -- 16 bit
                else
                    ram_dq_i <= dataOut_write_data & "00000000";--std_logic_vector(resize(unsigned(dataOut_write_data), ram_dq_i'length)); -- 8 bit
                end if;
							
				state_next <= STATE_WRITE_WAIT;
				
				-- start counter
				start_counter <= '1';
				
			when STATE_WRITE_WAIT =>				
				if cnt_write = '1' then -- wait for 260ns
					state_next <= STATE_IDLE;
				end if;
				
			when STATE_RAM_READ_FIFO =>
			
			if (empty_read_add = '0') and (full_read_data = '0') then
                read_dataOut_add <= '1'; -- reads address from FIFO
                write_dataOut_data <= '1'; -- writes data to FIFO
                 state_next <= STATE_RAM_READ;
            else
                read_dataOut_add <= '0'; -- disable read for FIFO
                write_dataOut_data <= '0'; -- disable write for FIFO
                 state_next <= STATE_IDLE;
            end if;
                       
			when STATE_RAM_READ =>
			
				-- set control signals
				ram_cen <= '0'; 
				ram_oen <= '0';
				ram_wen <= '1';
				
				ram_a <= dataOut_read_add; -- reads address from FIFO
					
--                if ENABLE_16_BIT = 1 then
--                    dataIn_read_data <= ram_dq_o; -- 16 bit
--                else
--                    dataIn_read_data <= std_logic_vector(resize(unsigned(ram_dq_o), dataIn_read_data'length)); -- 8 bit
--                end if;
				
				state_next <= STATE_READ_WAIT;
				
				-- start counter
				start_counter <= '1';
			
			when STATE_READ_WAIT =>
				if cnt_read = '1' then -- wait for 210ns
				    start_counter <= '0';
				    if ENABLE_16_BIT = 1 then
                        dataIn_read_data <= ram_dq_o; -- 16 bit
                    else
                        dataIn_read_data <= ram_dq_o(15 downto 8); -- std_logic_vector(resize(unsigned(ram_dq_o), dataIn_read_data'length)); -- 8 bit
                    end if;
					state_next <= STATE_IDLE;
				end if;
				
			when others =>
				state_next <= STATE_IDLE; 
	
		end case;
	end process sync_proc_ram;
			
-------------------------------------------------------------------------------
--
-- Process mem_ready_proc: triggered by full_read_data, full_read_add, full_write_data, full_write_add
-- checks if buffers are full => if memory mangement is ready to work
--
	mem_ready_proc: process (full_read_data, full_read_add, full_write_data, full_write_add)
	begin
		if full_read_data = '1' or full_read_add = '1' or full_write_data = '1' or full_write_add = '1' then
			mem_ready <= '0';
		else
			mem_ready <= '1';
		end if;
	end process mem_ready_proc;
		
end beh;
--
-------------------------------------------------------------------------------