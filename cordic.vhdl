--! @title CORDIC
--! @author by Asbjoern Magnus Midtboe 
--! @date 25/02-23

--! This is is a CORDIC using the AXIS interface. This module calculates the
--! absolute value of a complex number.
--! The module accepts a complex number per clock cycle. 
--! They are organized in the standard form of, MSB to LSB, IM - R. 
--! The output is a single unsigned number.


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cordic is
    generic(
        WIDTH : natural := 32;  --!IO with per number
        ITER  : natural := 13   --!Number of cordic iterations 
    );
    port(
        aclk            : in  std_logic;
        arstn           : in  std_logic;
        s_axis_tvalid   : in  std_logic;
        s_axis_tready   : out std_logic;
        s_axis_tlast    : in  std_logic;
        s_axis_tdata    : in  std_logic_vector(WIDTH * 2 - 1 downto 0);
        m_axis_tvalid   : out std_logic;
        m_axis_tready   : in  std_logic;
        m_axis_tlast    : out std_logic;
        m_axis_tdata    : out std_logic_vector(WIDTH - 1 downto 0) -- Unsigned output
    );
end entity cordic;

architecture rtl of cordic is
    --Two bits added to accomodate max theoretical magnitude
    type t_vector is array (0 to ITER) of signed(WIDTH + 1 downto 0);
    signal x_vector : t_vector;
    signal y_vector : t_vector;
    signal arst     : std_logic;
    signal last     : std_logic_vector(ITER downto 0);
    signal valid    : std_logic_vector(ITER downto 0);

begin 

    arst <= not arstn;
    m_axis_tdata  <= std_logic_vector(x_vector(ITER)(WIDTH downto 1)); --Will be positive, so converted to unsinged and truncated 
    m_axis_tvalid <= valid(ITER);
    m_axis_tlast  <= last(ITER);
    s_axis_tready <= m_axis_tready;

    CORDIC_PIPE : for i in 0 to ITER generate --increase iterations for more accuracy
        
        EXE : process(aclk) begin
            if rising_edge(aclk) then
                if arst = '1' then
                    x_vector(i) <= (others => '0');
                    y_vector(i) <= (others => '0');
                    valid(i) <= '0';
                    last(i)  <= '0';
                else
                    if i = 0 then
                        if m_axis_tready = '1' and s_axis_tvalid = '1' then
                            x_vector(i) <= resize(signed(s_axis_tdata(WIDTH - 1 downto 0)), WIDTH + 2);
                            y_vector(i) <= resize(signed(s_axis_tdata(WIDTH * 2 - 1 downto WIDTH)), WIDTH + 2);

                        end if;

                        if m_axis_tready = '1' then 
                            valid(i) <= s_axis_tvalid;
                            last(i)  <= s_axis_tlast;
                        end if;
                    elsif i = 1  then --Change the real value to positive if negative
                        if m_axis_tready = '1' then
                            if x_vector(i - 1)(WIDTH + 1) = '0' then 
                                x_vector(i) <= x_vector(i - 1);
                            else
                                x_vector(i) <= -x_vector(i - 1);
                            end if;
                            y_vector(i) <= y_vector(i - 1);

                            valid(i) <= valid(i - 1);
                            last(i)  <= last(i - 1);
                        end if;
                    elsif m_axis_tready = '1' then
                        if y_vector(i - 1)(WIDTH + 1) = '1' then
                            x_vector(i) <= x_vector(i - 1) - shift_right(y_vector(i - 1), i - 2);
                            y_vector(i) <= y_vector(i - 1) + shift_right(x_vector(i - 1), i - 2);
                        else
                            x_vector(i) <= x_vector(i - 1) + shift_right(y_vector(i - 1), i - 2);
                            y_vector(i) <= y_vector(i - 1) - shift_right(x_vector(i - 1), i - 2);
                            
                        end if;
                        valid(i) <= valid(i - 1);
                        last(i)  <= last(i - 1);
                    end if;
                end if;
            end if;
        end process;

    end generate;

end rtl;
