--! @title Partial Cross-Correlation
--! @author by Asbjoern Magnus Midtboe 
--! @date 19/03-23

--! This is is a partial CC module that performs calulations for a single direction
--! using the AXIS interface. 
--! The module accepts two complex numbers parallely. 
--! They are organized in the standard form of, MSB to LSB, IM2 - R2 - IM1 - R1. 
--! The the module connects the modules CMULT, xFFT, CORDIC, and EVAL.
--! The output consit of, MSB to LSB,  Argmax and Max. 

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity partialCC is
    port(
        aclk            : in  std_logic;
        arstn           : in  std_logic;
        s_axis_tvalid   : in  std_logic;
        s_axis_tready   : out std_logic;
        s_axis_tlast    : in  std_logic;
        s_axis_tdata    : in  std_logic_vector(127 downto 0); 
        m_axis_tvalid   : out std_logic;
        m_axis_tready   : in  std_logic;
        m_axis_tlast    : out std_logic;
        m_axis_tdata    : out std_logic_vector(63 downto 0) --Arg & mag
    );
end;

architecture rtl of partialCC is

    component cmult
        generic(
            IO_WIDTH    : natural := 32; --For single number
            CAL_WIDTH   : natural := 19  --Max is 28 (from fft)
        );
        port(
            aclk            : in  std_logic;
            arstn           : in  std_logic;
            s_axis_tready   : out std_logic;
            s_axis_tvalid   : in  std_logic;
            s_axis_tlast    : in  std_logic;
            s_axis_tdata    : in  std_logic_vector(IO_WIDTH*4 - 1 downto 0);
            m_axis_tready   : in  std_logic;
            m_axis_tvalid   : out std_logic;
            m_axis_tlast    : out std_logic;
            m_axis_tdata    : out std_logic_vector(IO_WIDTH*2 - 1 downto 0)
        );
    end component;

    component xfft_0
        port (
            aclk                        : in  std_logic;
            aresetn                     : in  std_logic;
            s_axis_config_tdata         : in  std_logic_vector(15 DOWNTO 0);
            s_axis_config_tvalid        : in  std_logic;
            s_axis_config_tready        : out std_logic;
            s_axis_data_tdata           : in  std_logic_vector(63 DOWNTO 0);
            s_axis_data_tvalid          : in  std_logic;
            s_axis_data_tready          : out std_logic;
            s_axis_data_tlast           : in  std_logic;
            m_axis_data_tdata           : out std_logic_vector(63 DOWNTO 0);
            m_axis_data_tvalid          : out std_logic;
            m_axis_data_tready          : in  std_logic;
            m_axis_data_tlast           : out std_logic;
            event_frame_started         : out std_logic;
            event_tlast_unexpected      : out std_logic;
            event_tlast_missing         : out std_logic;
            event_status_channel_halt   : out std_logic;
            event_data_in_channel_halt  : out std_logic;
            event_data_out_channel_halt : out std_logic
        );
    end component;

    component cordic 
        generic(
            WIDTH : natural := 32; --Times two (imag and real)
            ITER  : natural := 13
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
    end component;

    component eval
        generic(
            WIDTH : natural := 32;
            IMSIZE: natural := 512
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
    end component;

    --Cmult to FFT signals
    signal fft2cmult_tready : std_logic;
    signal cmult2fft_tvalid : std_logic;
    signal cmult2fft_tlast  : std_logic;
    signal cmult2fft_tdata  : std_logic_vector(63 downto 0);

    --FFT to cordic signals
    signal cordic2fft_tready : std_logic;
    signal fft2cordic_tvalid : std_logic;
    signal fft2cordic_tlast  : std_logic;
    signal fft2cordic_tdata  : std_logic_vector(63 downto 0);

    --FFT hanging signals
    signal efs      : std_logic;
    signal etu      : std_logic;
    signal etm      : std_logic;
    signal esch     : std_logic;
    signal edich    : std_logic;  
    signal edoch    : std_logic;  

    --FFT config signals
    signal fft_conf_tdata  : std_logic_vector(15 downto 0);
    signal fft_conf_tvalid : std_logic;
    signal fft_conf_tready : std_logic;

    --Cordic to eval
    signal eval2cordic_tready : std_logic;
    signal cordic2eval_tvalid : std_logic;
    signal cordic2eval_tlast  : std_logic;
    signal cordic2eval_tdata  : std_logic_vector(31 downto 0);


begin
                                 
    fft_conf_tdata  <= "00000" & "0001010101" & '0';
    
    config : process(aclk) begin
        if rising_edge(aclk) then
            if arstn = '0' then
                fft_conf_tvalid <= '1'; 
            else
                if fft_conf_tready = '1' then
                    fft_conf_tvalid <= '0';
                end if;
            end if;
        end if;
    end process;


    multiplier : cmult 
        generic map (
            IO_WIDTH    => 32, --For single number (real or imag)
            CAL_WIDTH   => 19  --Max is 28
        )
        port map (
            aclk            =>  aclk,
            arstn           =>  arstn,
            s_axis_tready   =>  s_axis_tready,
            s_axis_tvalid   =>  s_axis_tvalid,
            s_axis_tlast    =>  s_axis_tlast,
            s_axis_tdata    =>  s_axis_tdata,
            m_axis_tready   =>  fft2cmult_tready,
            m_axis_tvalid   =>  cmult2fft_tvalid,
            m_axis_tlast    =>  cmult2fft_tlast,
            m_axis_tdata    =>  cmult2fft_tdata
        ); 

    
    fft : xfft_0
        port map (
            aclk                        => aclk,
            aresetn                     => arstn,
            s_axis_config_tdata         => fft_conf_tdata,
            s_axis_config_tvalid        => fft_conf_tvalid,
            s_axis_config_tready        => fft_conf_tready,
            s_axis_data_tdata           => cmult2fft_tdata,
            s_axis_data_tvalid          => cmult2fft_tvalid,
            s_axis_data_tready          => fft2cmult_tready,
            s_axis_data_tlast           => cmult2fft_tlast,
            m_axis_data_tdata           => fft2cordic_tdata,
            m_axis_data_tvalid          => fft2cordic_tvalid,
            m_axis_data_tready          => cordic2fft_tready,
            m_axis_data_tlast           => fft2cordic_tlast,
            event_frame_started         => efs,
            event_tlast_unexpected      => etu,
            event_tlast_missing         => etm,
            event_status_channel_halt   => esch,
            event_data_in_channel_halt  => edich,
            event_data_out_channel_halt => edoch
        );


    absolute : cordic
        generic map (
            WIDTH => 32, 
            ITER  => 13
        )
        port map (
            aclk            =>  aclk,
            arstn           =>  arstn,
            s_axis_tready   =>  cordic2fft_tready,
            s_axis_tvalid   =>  fft2cordic_tvalid,
            s_axis_tlast    =>  fft2cordic_tlast,
            s_axis_tdata    =>  fft2cordic_tdata,
            m_axis_tready   =>  eval2cordic_tready,
            m_axis_tvalid   =>  cordic2eval_tvalid,
            m_axis_tlast    =>  cordic2eval_tlast,
            m_axis_tdata    =>  cordic2eval_tdata
        );

    maximum : eval 
        generic map (
            WIDTH   => 32,
            IMSIZE  => 512
        )
        port map (
            aclk            =>  aclk,
            arstn           =>  arstn,
            s_axis_tready   =>  eval2cordic_tready,
            s_axis_tvalid   =>  cordic2eval_tvalid,
            s_axis_tlast    =>  cordic2eval_tlast,
            s_axis_tdata    =>  cordic2eval_tdata,
            m_axis_tready   =>  m_axis_tready,
            m_axis_tvalid   =>  m_axis_tvalid,
            m_axis_tlast    =>  m_axis_tlast,
            m_axis_tdata    =>  m_axis_tdata
        );

    
end architecture;
