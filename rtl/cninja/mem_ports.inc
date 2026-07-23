`ifdef JTFRAME_SRAM
    output    [16:0]  sram_addr,
    output    [15:0]  sram_din,
    input     [15:0]  sram_dout,
    output            sram_wen,
    output    [ 1:0]  sram_dsn,
    input             sram_ok,
`endif
    input cen1p5, cen3, cen6, // 6000000 = 48000000*1/8 Hz 

    // Audio channels
    
    output signed [15:0] opn,
    output [ 9:0] psg,output signed [15:0] opm_l,
    output signed [15:0] opm_r,
    output signed [13:0] pcm1,
    output signed [13:0] pcm2,
    // Memory ports
`ifdef JTFRAME_SDRAM_XL
    input   [23:0]  prog_addr,
`elsif JTFRAME_SDRAM_LARGE
    input   [22:0]  prog_addr,
`else
    input   [21:0]  prog_addr,
`endif
    input   [ 7:0]  prog_data,
    input           prog_we,
    input   [ 1:0]  prog_ba,
    input   [25:0]  ioctl_addr,
    input           prom_we,
`ifdef JTFRAME_SDRAM_XL
    output reg [23:0] post_addr,
`elsif JTFRAME_SDRAM_LARGE
    output reg [22:0] post_addr,
`else
    output reg [21:0] post_addr,
`endif

    output reg [ 7:0] post_data,

`ifdef JTFRAME_HEADER
    input           header,
`endif
`ifdef JTFRAME_IOCTL_RD
    input           ioctl_wr,
    output   [ 7:0] ioctl_din,
    input    [ 7:0] ioctl_dout, `endif
    input           ioctl_ram,
    input           ioctl_cart,
    // Explicit ports
    output   [15:0] main_dout,
    output   [15:0] snd_addr,
    input   [7:0] snd_data,
    // Buses to BRAM

    
    // Buses to SDRAM
    input    [31:0] objrom_data,
    output          objrom_cs,
    output   [20:2] objrom_addr,
    input           objrom_ok,

    input    [31:0] scr2_data,
    output          scr2_cs,
    output   [19:2] scr2_addr,
    input           scr2_ok,

    input    [15:0] main_data,
    output          main_cs,
    output   [19:1] main_addr,
    input           main_ok,

    input    [ 7:0] oki1_data,
    output          oki1_cs,
    output   [17:0] oki1_addr,
    input           oki1_ok,

    input    [ 7:0] oki2_data,
    output          oki2_cs,
    output   [18:0] oki2_addr,
    input           oki2_ok,

    input    [31:0] scr3_data,
    output          scr3_cs,
    output   [19:2] scr3_addr,
    input           scr3_ok,

    input    [31:0] char_data,
    output          char_cs,
    output   [16:2] char_addr,
    input           char_ok,

    input    [31:0] scr1_data,
    output          scr1_cs,
    output   [18:2] scr1_addr,
    input           scr1_ok
