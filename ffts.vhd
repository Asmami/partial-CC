--! @title Novel 2D FFT
--! @author Asbjoern Magnus Midtboe
--! @date 16/05-23

--! This module performs an FFT on every row/col of an image before reodering 
--! and taking a single FFT of col/row. The input width is the number of FFT times the
--! bit width of a single pixel. The output is in the, MSB to LSB, IM - R form.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ffts is
    generic(
        par_cnt : natural := 64 --!Parallel FFTs
    );
    port(
        aclk            : in  std_logic;
        arstn           : in  std_logic;
        s_axis_tvalid   : in  std_logic;
        s_axis_tready   : out std_logic;
        s_axis_tlast    : in  std_logic;
        s_axis_tdata    : in  std_logic_vector(par_cnt*8 -1 downto 0); 
        m_axis_tvalid   : out std_logic;
        m_axis_tready   : in  std_logic;
        m_axis_tlast    : out std_logic;
        m_axis_tdata    : out std_logic_vector(63 downto 0)
    );
end;


architecture rtl of ffts is

    COMPONENT xfft_0
    PORT (
        aclk : IN STD_LOGIC;
        aresetn : IN STD_LOGIC;
        s_axis_config_tdata : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
        s_axis_config_tvalid : IN STD_LOGIC;
        s_axis_config_tready : OUT STD_LOGIC;
        s_axis_data_tdata : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        s_axis_data_tvalid : IN STD_LOGIC;
        s_axis_data_tready : OUT STD_LOGIC;
        s_axis_data_tlast : IN STD_LOGIC;
        m_axis_data_tdata : OUT STD_LOGIC_VECTOR(47 DOWNTO 0);
        m_axis_data_tuser : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        m_axis_data_tvalid : OUT STD_LOGIC;
        m_axis_data_tready : IN STD_LOGIC;
        m_axis_data_tlast : OUT STD_LOGIC;
        event_frame_started : OUT STD_LOGIC;
        event_tlast_unexpected : OUT STD_LOGIC;
        event_tlast_missing : OUT STD_LOGIC;
        event_status_channel_halt : OUT STD_LOGIC;
        event_data_in_channel_halt : OUT STD_LOGIC;
        event_data_out_channel_halt : OUT STD_LOGIC 
    );
    END COMPONENT;

    COMPONENT xfft_1
    PORT (
        aclk : IN STD_LOGIC;
        aresetn : IN STD_LOGIC;
        s_axis_config_tdata : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
        s_axis_config_tvalid : IN STD_LOGIC;
        s_axis_config_tready : OUT STD_LOGIC;
        s_axis_data_tdata : IN STD_LOGIC_VECTOR(47 DOWNTO 0);
        s_axis_data_tvalid : IN STD_LOGIC;
        s_axis_data_tready : OUT STD_LOGIC;
        s_axis_data_tlast : IN STD_LOGIC;
        m_axis_data_tdata : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
        m_axis_data_tvalid : OUT STD_LOGIC;
        m_axis_data_tready : IN STD_LOGIC;
        m_axis_data_tlast : OUT STD_LOGIC;
        event_frame_started : OUT STD_LOGIC;
        event_tlast_unexpected : OUT STD_LOGIC;
        event_tlast_missing : OUT STD_LOGIC;
        event_status_channel_halt : OUT STD_LOGIC;
        event_data_in_channel_halt : OUT STD_LOGIC;
        event_data_out_channel_halt : OUT STD_LOGIC 
    );
    END COMPONENT;

    constant check      : std_logic_vector(par_cnt - 1 downto 0) := (others => '1'); 

    --AXIS signals
    type t_data_in  is array (0 to par_cnt - 1) of std_logic_vector(15 downto 0);
    type t_data_out is array (0 to par_cnt - 1) of std_logic_vector(47 downto 0);
    signal data_in      : t_data_in;
    signal data_out     : t_data_out;
    signal user_out     : t_data_in;

    signal ready_in     : std_logic_vector(par_cnt - 1 downto 0);

    signal valid_out    : std_logic_vector(par_cnt - 1 downto 0);
    signal ready_out    : std_logic_vector(par_cnt - 1 downto 0);
    signal last_out     : std_logic_vector(par_cnt - 1 downto 0);

    signal single_data_in : std_logic_vector(47 downto 0);
    signal single_valid_in: std_logic;
    signal single_ready_in: std_logic;
    signal single_last_in : std_logic;

    --FFT config signals
    signal fft_conf_tdata  : std_logic_vector(7 downto 0);
    signal fft_conf_tvalid : std_logic;
    signal fft_conf_tready : std_logic_vector(par_cnt - 1 downto 0);
    signal fft_conf_tready2: std_logic;

    --FFT hanging signals
    signal efs      : std_logic_vector(par_cnt - 1 downto 0);
    signal etu      : std_logic_vector(par_cnt - 1 downto 0);
    signal etm      : std_logic_vector(par_cnt - 1 downto 0);
    signal esch     : std_logic_vector(par_cnt - 1 downto 0);
    signal edich    : std_logic_vector(par_cnt - 1 downto 0);  
    signal edoch    : std_logic_vector(par_cnt - 1 downto 0);
    signal efs2     : std_logic;
    signal etu2     : std_logic;
    signal etm2     : std_logic;
    signal esch2    : std_logic;
    signal edich2   : std_logic;  
    signal edoch2   : std_logic;   

    --Counters
    signal frame_cnt : integer range 0 to 512 / par_cnt;
    signal row_cnt   : integer range 0 to par_cnt;


    signal transfer  : std_logic; 
    

begin

    s_axis_tready <= '1' when ready_in = check else '0';      

    fft_conf_tdata  <= "0000000" & '1';

    config : process(aclk) begin
        if rising_edge(aclk) then
            if arstn = '0' then
                fft_conf_tvalid <= '1'; 
            else
                if fft_conf_tready = check and fft_conf_tready2 = '1'  then
                    fft_conf_tvalid <= '0';
                end if;
            end if;
        end if;
    end process;

    data : process(s_axis_tdata) begin
        for i in 0 to par_cnt - 1  loop
            data_in(i) <= "00000000" & s_axis_tdata(8*(i+1) - 1 downto i*8); 
        end loop; --   
    end process;
    
    ordering : process(aclk) begin
        if rising_edge(aclk) then
            if arstn = '0' then 
                ready_out       <= (others => '1');
                single_data_in  <= (others => '0'); 
                single_valid_in <= '0';
                single_last_in  <= '0';
                transfer        <= '0';
                row_cnt         <= 0;
                frame_cnt       <= 0;
            else
                if user_out(0) = std_logic_vector(to_unsigned(416, 16)) then
                    ready_out <= (others => '0'); 
                    transfer  <= '1';
                end if;

                if transfer = '1' then
                   
                    if row_cnt = par_cnt and single_ready_in = '1' then
                        single_valid_in <= '0';
                        ready_out       <= (others => '1');
                        frame_cnt       <= frame_cnt + 1;
                        row_cnt         <= 0;
                        transfer        <= '0';
                    else
                        if valid_out(row_cnt) = '1' and single_ready_in = '1' then
                            single_valid_in <= '1';
                            single_data_in  <= data_out(row_cnt);
                            row_cnt <= row_cnt + 1;
                        else
                            single_valid_in <= '0';
                        end if;
                    end if;    
                end if;

                if frame_cnt = (512/par_cnt) - 1 and row_cnt = par_cnt - 1 then 
                    single_last_in <= '1';
                    frame_cnt <= 0;
                else 
                    single_last_in <= '0';
                end if;

                if single_last_in = '1' then
                    frame_cnt <= 0;
                end if; 
            end if;
        end if;
    end process;

    single : xfft_1
    PORT MAP (
        aclk =>                         aclk,
        aresetn =>                      arstn,
        s_axis_config_tdata =>          fft_conf_tdata,
        s_axis_config_tvalid =>         fft_conf_tvalid,
        s_axis_config_tready =>         fft_conf_tready2,
        s_axis_data_tdata =>            single_data_in,
        s_axis_data_tvalid =>           single_valid_in,
        s_axis_data_tready =>           single_ready_in,
        s_axis_data_tlast =>            single_last_in,
        m_axis_data_tdata =>            m_axis_tdata,
        m_axis_data_tvalid =>           m_axis_tvalid,
        m_axis_data_tready =>           m_axis_tready,
        m_axis_data_tlast =>            m_axis_tlast,--last_1024,
        event_frame_started =>          efs2,   
        event_tlast_unexpected =>       etu2,   
        event_tlast_missing =>          etm2,   
        event_status_channel_halt =>    esch2,  
        event_data_in_channel_halt =>   edich2, 
        event_data_out_channel_halt =>  edoch2
    );


    ftts : for i in 0 to par_cnt - 1 generate
        multiple : xfft_0
        PORT MAP (
            aclk =>                         aclk,
            aresetn =>                      arstn,
            s_axis_config_tdata =>          fft_conf_tdata,
            s_axis_config_tvalid =>         fft_conf_tvalid,
            s_axis_config_tready =>         fft_conf_tready(i),
            s_axis_data_tdata =>            data_in(i),
            s_axis_data_tvalid =>           s_axis_tvalid,
            s_axis_data_tready =>           ready_in(i),
            s_axis_data_tlast =>            s_axis_tlast,
            m_axis_data_tdata =>            data_out(i),
            m_axis_data_tuser =>            user_out(i),
            m_axis_data_tvalid =>           valid_out(i),
            m_axis_data_tready =>           ready_out(i),
            m_axis_data_tlast =>            last_out(i),
            event_frame_started =>          efs(i),   
            event_tlast_unexpected =>       etu(i),   
            event_tlast_missing =>          etm(i),   
            event_status_channel_halt =>    esch(i),  
            event_data_in_channel_halt =>   edich(i), 
            event_data_out_channel_halt =>  edoch(i) 
        );
    end generate;

end architecture;