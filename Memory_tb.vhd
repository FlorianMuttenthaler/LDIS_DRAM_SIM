-------------------------------------------------------------------------------
--
-- Memory Interface Testbench
-- NOTE: Testbench used to test the memory interface
--
-------------------------------------------------------------------------------
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.memory_pkg.all;

--  A testbench has no ports.
entity memory_tb is
end memory_tb;
--
-------------------------------------------------------------------------------
--
architecture beh of memory_tb is

	-- Specifies which entity is bound with the component.
	for memory_0: memory use entity work.memory;	

	constant CLK_PERIOD			: time := 5 ns;
	
	constant ENABLE_16_BIT		: integer := 1; -- 16 bit
	constant FIFO_DEPTH_WRITE	: integer := 8;
	constant FIFO_DEPTH_READ  	: integer := 8;
	
	signal clk_200MHz 			: std_logic := '0';

	signal rst 					: std_logic; -- active high system reset
    signal address 				: std_logic_vector(26 downto 0); -- address space
    signal data_in 				: std_logic_vector((8 * (1 + ENABLE_16_BIT)) - 1 downto 0); -- data byte input
	signal r_w					: std_logic; -- Read or Write flag
	signal mem_ready 			: std_logic; -- allocated memory ready or busy flag
    signal data_out 			: std_logic_vector((8 * (1 + ENABLE_16_BIT)) - 1 downto 0); -- data byte output

begin

	-- Component instantiation.
	memory_0: memory
		generic map(
			ENABLE_16_BIT 		=> ENABLE_16_BIT,
			FIFO_DEPTH_WRITE 	=> FIFO_DEPTH_WRITE,
			FIFO_DEPTH_READ 	=> FIFO_DEPTH_READ	
		)
			
		port map (
			clk_200MHz			=> clk_200MHz,
      		rst 				=> rst,
			address 			=> address,
			data_in 			=> data_in,
			r_w					=> r_w,
			mem_ready 			=> mem_ready,
			data_out 			=> data_out
		);
--
--------------------------------------------------------------------------------
--
	clk_process : process
	
	begin
		clk_200MHz <= '0';
		wait for CLK_PERIOD/2;
		clk_200MHz <= '1';
		wait for CLK_PERIOD/2;

	end process clk_process;	
--
--------------------------------------------------------------------------------
--  This process does the real job.
--
	stimuli : process

	begin
        
        rst <= '0';
		wait for 100 ns;
		
        --Buffer test
		
        r_w <= '1'; -- write
		
        address <= "000000000000000000000000100";
        data_in <= "0000010000000100";
        
        wait for 10 ns;
        
        address <= "000000000000000000000000101";
        data_in <= "0000101000000101";
        
		wait for 10 ns;
        
        address <= "000000000000000000000000110";
        data_in <= "0000011000000110";
        
		wait for 10 ns;
        
        address <= "000000000000000000000000111";
        data_in <= "0000011100000111";
        
		wait for 10 ns;
        
        address <= "000000000000000000000001000";
        data_in <= "0000101000001000";
        
		wait for 10 ns;
        
        address <= "000000000000000000000001001";
        data_in <= "0000011000001001";
        
		wait for 10 ns;
        
        address <= "000000000000000000000001010";
        data_in <= "0000010000001010";
        
		wait for 10 ns;
        
        address <= "000000000000000000000001011";
        data_in <= "0000101000001011";
        
		wait for 10 ns;
		  
		assert mem_ready = '0' report "Buffer overflow" severity error;
		  
		while mem_ready = '0' loop
			wait for 10 ns; -- wait until FIFO is not full
		end loop;
		  
		wait for 10 ns;
		  
        address <= "000000000000000000000001100";
        data_in <= "0000011000001100";
        
		wait for 10 ns;
		  
        assert mem_ready = '0' report "Buffer overflow" severity error;
        
        wait for 10000 ns;
			
		------------------------------------------------------------------
		
		r_w <= '0'; -- read
		
        address <= "000000000000000000000000100";
        assert data_out = "0000010000000100" report "Valid data output" severity error;
        
		wait for 10 ns;
        
        address <= "000000000000000000000000101";
        assert data_out = "0000101000000101" report "Valid data output" severity error;
        
		wait for 10 ns;
        
        address <= "000000000000000000000000110";
        assert data_out = "0000011000000110" report "Valid data output" severity error;
        
		wait for 10 ns;
        
        address <= "000000000000000000000000111";
        assert data_out = "0000011100000111" report "Valid data output" severity error;
        
		wait for 10 ns;
        
        address <= "000000000000000000000001000";
        assert data_out = "0000101000001000" report "Valid data output" severity error;
        
		wait for 10 ns;
        
        address <= "000000000000000000000001001";
        assert data_out = "0000011000001001" report "Valid data output" severity error;
        
		wait for 10 ns;
        
        address <= "000000000000000000000001010";
        assert data_out = "0000010000001010" report "Valid data output" severity error;
        
		wait for 10 ns;
        
        address <= "000000000000000000000001011";
        assert data_out = "0000101000001011" report "Valid data output" severity error;
        
		wait for 10 ns;
		  
		assert mem_ready = '0' report "Buffer overflow" severity error;
		  
		while mem_ready = '0' loop
			wait for 100 ns; -- wait until FIFO is not full
		end loop;
        
        address <= "000000000000000000000001100";
        assert data_out = "0000011000001100" report "Valid data output" severity error;
        
		wait for 10 ns;
        
        assert mem_ready = '0' report "Buffer overflow" severity error;
        
        wait for 10000 ns;
        
		assert false report "end of test" severity failure;

		--  Wait forever; this will finish the simulation.
		wait;

	end process stimuli;

end beh;
--
-------------------------------------------------------------------------------
