--! @title Argmax and Maximum 
--! @author Asbjoern Magnus Midtboe
--! @date 28/02-23

--! This is an argmax and maximum module using an AXIS interface. 
--! The input accepts a single unsigned number per clock cycle.
--! When reciving it is evaluated if the new value was higher than the current high.
--! Tlast is recived when every for every row/col completion. The packet length is the same as image size.  
--! In its current configuration it is counting 1024 tlast signals before giving tlast.
--! This is for testing.
--! The output consit of, MSB to LSB,  Argmax and Max. 


--This module oly hanles positive numbers (unsigned)


Library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.math_real.all;

entity eval is 
    generic(
        WIDTH : natural := 32; --!IO width per number
        IMSIZE: natural := 512 --!Image size
    );
    port(
        aclk            : in  std_logic;
        arstn           : in  std_logic;
        s_axis_tvalid   : in  std_logic;
        s_axis_tready   : out std_logic;
        s_axis_tlast    : in  std_logic;
        s_axis_tdata    : in  std_logic_vector(WIDTH - 1 downto 0); -- Unsigned
        m_axis_tvalid   : out std_logic;
        m_axis_tready   : in  std_logic;
        m_axis_tlast    : out std_logic;
        m_axis_tdata    : out std_logic_vector(WIDTH*2 - 1 downto 0) --Arg & mag
    );
end entity eval;

architecture rtl of eval is

    constant IMWID      : natural := natural(ceil(log2(real(IMSIZE))));

    signal arst         : std_logic;
    signal magnitude_in : std_logic_vector(WIDTH - 1 downto 0);
    signal magnitude    : std_logic_vector(WIDTH - 1 downto 0);
    signal argmax       : std_logic_vector(IMWID - 1 downto 0);
    signal magnitude_out: std_logic_vector(WIDTH - 1 downto 0);
    signal argmax_out   : std_logic_vector(IMWID - 1 downto 0);

    signal valid        : std_logic;
    signal ready        : std_logic;
    signal last, last_d : std_logic;
    signal last_true    : std_logic;

    signal arg_cnt      : integer range 0 to IMSIZE;
    signal frame_cnt    : integer range 0 to 1024;

begin

    m_axis_tvalid <= valid;
    s_axis_tready <= ready;
    m_axis_tlast  <= last_true; --This is kinda stupid
    ready         <= '0' when last_d = '1' or last = '1' or (valid = '1' and arg_cnt > IMSIZE - 2)  else '1';

    m_axis_tdata(WIDTH - 1 downto 0)                <= magnitude_out; 
    m_axis_tdata(WIDTH + IMWID - 1 downto WIDTH)    <= argmax_out; 
    m_axis_tdata(WIDTH*2 - 1 downto WIDTH + IMWID)  <= (others => '0');
    
    arst <= not arstn;

    P1 : process(aclk) begin
        if rising_edge(aclk) then
            if arst = '1' then
                magnitude_in  <= (others => '0');
                magnitude     <= (others => '0');
                argmax        <= (others => '0');
                magnitude_out <= (others => '0');
                argmax_out    <= (others => '0');
                valid         <= '0';
                arg_cnt       <= 0;
                frame_cnt     <= 0;
                last_true     <= '0';
            else

                last <= s_axis_tlast and ready;
                last_d <= last;

                if s_axis_tvalid = '1' and ready = '1' then
                    magnitude_in <= s_axis_tdata;
                    arg_cnt <= arg_cnt + 1;
                end if;

                
                if unsigned(magnitude) < unsigned(magnitude_in) then
                    magnitude <= magnitude_in;
                    argmax    <= std_logic_vector(to_unsigned(arg_cnt - 1, IMWID)); 
                end if;

                if last = '1' then
                    magnitude_in  <= (others => '0');
                end if;

                if last_d = '1' then 
                    valid         <= '1';
                    magnitude_out <= magnitude;
                    magnitude     <= (others => '0');
                    argmax_out    <= argmax;
                    argmax        <= (others => '0');
                    arg_cnt       <= 0;
                    if frame_cnt = 1023 then
                        frame_cnt <= 0;
                        last_true <= '1';
                    else
                        frame_cnt <= frame_cnt + 1;
                        last_true <= '0';
                    end if;
                end if;

                if m_axis_tready = '1' and valid = '1' then
                    valid         <= '0';
                    last_true     <= '0';
                    magnitude_out <= (others => '0');
                    argmax_out    <= (others => '0');
                end if;
               
            end if;
        end if;
    end process P1;

end rtl;
