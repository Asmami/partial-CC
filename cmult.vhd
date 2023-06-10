--! @title Complex Multiplier
--! @author by Asbjoern Magnus Midtboe 
--! @date 19/02-23

--! This is is a complex multiplier using the AXIS interface. 
--! The module accepts two complex numbers parralelly. 
--! They are organized in the standard form of, MSB to LSB, IM2 - R2 - IM1 - R1. 
--! The calculation width is currently configured to truncate MSB.
--! This is because the values used for testing is so low it does they are zero.
--! No truncation of the input occurs if CAL_WIDTH is set to 28.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cmult is
  generic (
    IO_WIDTH : natural := 32; --!IO width for single number (real or imaginary)
    CAL_WIDTH : natural := 19 --!Calculation width. Max is 28 (output of 2dFFT)
  );
  port (
    aclk : in std_logic;            
    arstn : in std_logic;           
    s_axis_tready : out std_logic;  
    s_axis_tvalid : in std_logic;
    s_axis_tlast : in std_logic;
    s_axis_tdata : in std_logic_vector(IO_WIDTH * 4 - 1 downto 0);
    m_axis_tready : in std_logic;
    m_axis_tvalid : out std_logic;
    m_axis_tlast : out std_logic;
    m_axis_tdata : out std_logic_vector(IO_WIDTH * 2 - 1 downto 0)
  );
end entity cmult;
architecture rtl of cmult is

  --Input registers
  signal ar_d : signed(CAL_WIDTH - 1 downto 0); 
  signal ai_d : signed(CAL_WIDTH - 1 downto 0); 
  signal br_d : signed(CAL_WIDTH - 1 downto 0); 
  signal bi_d : signed(CAL_WIDTH - 1 downto 0); 

  --Temp reg 1 (T)
  signal T1 : signed(CAL_WIDTH downto 0);       
  signal T2 : signed(CAL_WIDTH - 1 downto 0);   
  signal T3 : signed(CAL_WIDTH downto 0);       
  signal T4 : signed(CAL_WIDTH - 1 downto 0);   
  signal T5 : signed(CAL_WIDTH downto 0);       
  signal T6 : signed(CAL_WIDTH - 1 downto 0);   

  --Temp reg 2 (K)
  signal K1 : signed(CAL_WIDTH + CAL_WIDTH downto 0);   
  signal K2 : signed(CAL_WIDTH + CAL_WIDTH downto 0);   
  signal K3 : signed(CAL_WIDTH + CAL_WIDTH downto 0);   

  --Output registers
  signal re : signed(CAL_WIDTH + CAL_WIDTH downto 0);   
  signal im : signed(CAL_WIDTH + CAL_WIDTH downto 0);   

  --Tlast and tvalid delay
  signal last_d, last_dd, last_ddd, last_dddd : std_logic;      
  signal valid_d, valid_dd, valid_ddd, valid_dddd : std_logic;  

  signal arst : std_logic;

begin
  --Truncating to 32bit (lsb removed)
  m_axis_tdata <= std_logic_vector(im(CAL_WIDTH * 2 downto CAL_WIDTH * 2 - IO_WIDTH + 1)) & std_logic_vector(re(CAL_WIDTH * 2 downto CAL_WIDTH * 2 - IO_WIDTH + 1));

  s_axis_tready <= m_axis_tready;
  m_axis_tvalid <= valid_dddd;
  m_axis_tlast <= last_dddd;

  arst <= not arstn;

  DELAY : process (aclk) begin --!Delay AXIS signals
    if rising_edge(aclk) then
      if arst = '1' then
        last_d <= '0';   
        last_dd <= '0';
        last_ddd <= '0';
        last_dddd <= '0';
        valid_d <= '0';
        valid_dd <= '0';
        valid_ddd <= '0';
        valid_dddd <= '0';
      else
        if m_axis_tready = '1' then
          last_d <= s_axis_tlast;
          last_dd <= last_d;
          last_ddd <= last_dd;
          last_dddd <= last_ddd;
          valid_d <= s_axis_tvalid;
          valid_dd <= valid_d;
          valid_ddd <= valid_dd;
          valid_dddd <= valid_ddd;
        end if;
      end if;
    end if;
  end process;

  IP : process (aclk) begin
    if rising_edge(aclk) then
      if arst = '1' then
        ar_d <= (others => '0');
        ai_d <= (others => '0');
        br_d <= (others => '0');
        bi_d <= (others => '0');
      else
        if s_axis_tvalid = '1' and m_axis_tready = '1' then
          --Truncating down to CAL_WIDTH. Currenly this removing MSB. Change if DSP slice overuse.
          ar_d <= signed(s_axis_tdata(IO_WIDTH - 1) & s_axis_tdata(CAL_WIDTH - 2 downto 0));
          ai_d <= signed(s_axis_tdata(IO_WIDTH * 2 - 1) & s_axis_tdata(CAL_WIDTH + IO_WIDTH - 2 downto IO_WIDTH));
          br_d <= signed(s_axis_tdata(IO_WIDTH * 3 - 1) & s_axis_tdata(CAL_WIDTH + IO_WIDTH * 2 - 2 downto IO_WIDTH * 2));
          bi_d <= signed(s_axis_tdata(IO_WIDTH * 4 - 1) & s_axis_tdata(CAL_WIDTH + IO_WIDTH * 3 - 2 downto IO_WIDTH * 3));
        end if;
      end if;
    end if;
  end process;

  TP1 : process (aclk) begin
    if rising_edge(aclk) then
      if arst = '1' then
        T1 <= (others => '0');
        T2 <= (others => '0');
        T3 <= (others => '0');
        T4 <= (others => '0');
        T5 <= (others => '0');
        T6 <= (others => '0');
      else
        if m_axis_tready = '1' then
          T1 <= resize(ai_d, CAL_WIDTH + 1) - resize(ar_d, CAL_WIDTH + 1);
          T2 <= ar_d;
          T3 <= resize(ar_d, CAL_WIDTH + 1) + resize(ai_d, CAL_WIDTH + 1);
          T4 <= br_d;
          T5 <= resize(br_d, CAL_WIDTH + 1) + resize(bi_d, CAL_WIDTH + 1);
          T6 <= bi_d;
        end if;
      end if;
    end if;
  end process;

  TP2 : process (aclk) begin
    if rising_edge(aclk) then
      if arst = '1' then
        K1 <= (others => '0');
        K2 <= (others => '0');
        K3 <= (others => '0');
      else
        if m_axis_tready = '1' then
          K1 <= T2 * T5;
          K2 <= T3 * T6;
          K3 <= T1 * T4;
        end if;
      end if;
    end if;
  end process;

  OP : process (aclk) begin
    if rising_edge(aclk) then
      if arst = '1' then
        re <= (others => '0');
        im <= (others => '0');
      else
        if m_axis_tready = '1' then
          re <= K1 - K2;
          im <= K1 + K3;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;