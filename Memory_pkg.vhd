-------------------------------------------------------------------------------
--
-- Memory Interface package
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
package memory_pkg is

	component memory is

	-- 'ENABLE_16_BIT', 'FIFO_DEPTH_WRITE' and 'FIFO_DEPTH_READ' is the generic value of the entity.
	-- 'clk_200MHz', 'rst', 'address', 'data_in' and 'r_w' are the inputs of entity.
	-- 'mem_ready' and 'data_out' are the outputs of the entity.

	generic(
		ENABLE_16_BIT				: integer range 0 to 1 := 0; -- Default: 0 = disabled, 1 = enabled
		-- Size of FIFO buffers
		FIFO_DEPTH_WRITE			: integer := 8; -- Default: 8
		FIFO_DEPTH_READ  			: integer := 8  -- Default: 8	
	);
		
	port (
    	clk_200MHz      			: in  std_logic; -- 200 MHz system clock => 5 ns period time
		rst             			: in  std_logic; -- active high system reset
		address 	     				: in  std_logic_vector(26 downto 0); -- address space
		data_in          			: in  std_logic_vector((8 * (1 + ENABLE_16_BIT) - 1) downto 0); -- data byte input
		r_w			     			: in  std_logic; -- Read or Write flag: '1' ... write, '0' ... read
		mem_ready					: out std_logic; -- allocated memory ready or busy flag: '1' ... ready, '0' ... busy
		data_out         			: out std_logic_vector((8 * (1 + ENABLE_16_BIT) - 1) downto 0) -- data byte output
	);
	
	end component memory;
	
end memory_pkg;

