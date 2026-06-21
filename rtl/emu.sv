//============================================================================
//  Arcade: Data East DECO 16-bit (Caveman Ninja / Joe & Mac)
//
//  MiSTer-devel `emu` wrapper around the JOTEGO jtframe `cninja` core.
//  Clean rebuild on a pristine Template_MiSTer, vendoring inspired by the
//  working Arcade-BoogieWings_MiSTer core. Hosts jtframe's GENERATED game
//  wrapper (jtcninja_game_sdram) + jtframe's SDRAM glue (jtframe_board_sdram),
//  with pixel cens from jtframe_pxlcen and SDRAM_CLK = clk48sh (jtframe's
//  exact, proven config for this core).
//
//  GPLv3 — see rtl/cninja/jtcninja_game.v header.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////
assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_F1       = 0;
assign VGA_SCALER   = 0;
assign VGA_DISABLE  = 0;
assign HDMI_FREEZE  = 0;
assign HDMI_BLACKOUT  = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_MIX = 2'd0;   // core output is mono (L==R)

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

//////////////////////////////  ASPECT RATIO  ////////////////////////////////
// cninja is a horizontal 4:3 game (256x240).
wire [1:0] ar = status[14:13];
assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

//////////////////////////////   CONF_STR   //////////////////////////////////
`include "build_id.v"
localparam CONF_STR = {
	"Arcade-Deco16;;",
	"-;",
	"P1,Video Settings;",
	"P1O[14:13],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"P1-;",
	"P1O[34:32],Analog H-Size,0,1,2,3,4,5,6,7;",
	"P1O[39:35],Analog Video H-Pos,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[44:40],Analog Video V-Pos,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	"DIP;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"J1,Attack,Jump,Special,Start,Coin,Pause;",
	"jn,A,B,X,Start,Select,R;",
	"V,v",`BUILD_DATE
};

//////////////////////////////   CLOCKS   ////////////////////////////////////
// jtframe game PLL (vendored sys/pll): clk48 / clk48sh / clk24 / clk96.
wire clk48, clk48sh, clk24, clk96, clk96sh;
wire pll_locked;

pll pll
(
	.refclk   ( CLK_50M    ),
	.rst      ( 1'b0       ),
	.locked   ( pll_locked ),
	.outclk_0 ( clk48      ),
	.outclk_1 ( clk48sh    ),
	.outclk_2 ( clk24      ),
	.outclk_3 (            ),
	.outclk_4 ( clk96      ),
	.outclk_5 ( clk96sh    )
);

wire clk_sys = clk48;       // clk_sys == clk_rom == SDRAM clock domain

// SDRAM_CLK: jtframe's exact config for cninja (180SHIFT=0) — the PLL's
// phase-shifted 48 MHz output drives the SDRAM clock pin directly. Constrained
// as a generated clock in jtframe_sdram.sdc.
assign SDRAM_CLK = clk48sh;

//////////////////////////////   HPS IO   ////////////////////////////////////
wire [127:0] status;
wire   [1:0] buttons;
wire         forced_scandoubler;
wire         direct_video;
wire  [21:0] gamma_bus;
wire  [10:0] ps2_key;

wire  [31:0] joystick_0, joystick_1, joystick_2, joystick_3;

wire         ioctl_download;
wire         ioctl_wr;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire  [15:0] ioctl_index;
wire         ioctl_wait;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys            ( clk_sys            ),
	.HPS_BUS            ( HPS_BUS            ),
	.EXT_BUS            (                    ),

	.buttons            ( buttons            ),
	.status             ( status             ),
	.status_menumask    ( 16'd0              ),
	.forced_scandoubler ( forced_scandoubler ),
	.direct_video       ( direct_video       ),
	.gamma_bus          ( gamma_bus          ),

	.joystick_0         ( joystick_0         ),
	.joystick_1         ( joystick_1         ),
	.joystick_2         ( joystick_2         ),
	.joystick_3         ( joystick_3         ),

	.ioctl_download     ( ioctl_download     ),
	.ioctl_wr           ( ioctl_wr           ),
	.ioctl_addr         ( ioctl_addr         ),
	.ioctl_dout         ( ioctl_dout         ),
	.ioctl_index        ( ioctl_index        ),
	.ioctl_wait         ( ioctl_wait         ),

	.ps2_key            ( ps2_key            )
);

//////////////////////////////   RESET   /////////////////////////////////////
wire sdram_init;                       // from board_sdram (high while SDRAM trains)
wire dwnld_busy;                       // from game_sdram (ROM download in progress)

// SDRAM controller reset: hard reset / PLL-loss ONLY. It must run its init
// sequence and service the ROM download, so it must NOT be gated on sdram_init
// (its own output -> deadlock) or dwnld_busy.
wire rst_sd;
sync_rst u_rst_sd(.clk(clk48), .arst(RESET | ~pll_locked), .rst(rst_sd));

// Game reset: also held through SDRAM init, the ROM download and soft reset.
wire core_reset = RESET | status[0] | buttons[1] | ~pll_locked | sdram_init | dwnld_busy;
wire rst48, rst24, rst96;
sync_rst u_rst48(.clk(clk48), .arst(core_reset), .rst(rst48));
sync_rst u_rst24(.clk(clk24), .arst(core_reset), .rst(rst24));
sync_rst u_rst96(.clk(clk96), .arst(core_reset), .rst(rst96));

//////////////////////////////   DOWNLOAD   //////////////////////////////////
// MRA index 0 -> main ROM stream into the jtframe download path.
// DIPs arrive on index 254 (4 bytes).
wire        ioctl_rom = ioctl_download & (ioctl_index[15:0]==16'd0);

reg  [7:0]  dsw[0:3];
always @(posedge clk48) begin
	if (ioctl_wr && ioctl_index[15:0]==16'd254 && !ioctl_addr[24:2])
		dsw[ioctl_addr[1:0]] <= ioctl_dout;
end
wire [31:0] dipsw = {dsw[3], dsw[2], dsw[1], dsw[0]};

// Throttle the HPS while an SDRAM prog write is outstanding. prog_we is held
// from byte-latch until sdram_ack, and is 0 for BRAM(prom)/non-SDRAM bytes.
wire prog_we, prog_ack;
assign ioctl_wait = prog_we;

//////////////////////////////   INPUTS   ////////////////////////////////////
// jtframe cabinet inputs are ACTIVE-LOW (idle=1). MiSTer joystick bits are
// active-high; invert. The jtframe MRA <buttons> uses a 3-button family layout
// (so Caveman Ninja & Crude Buster share bit positions): bit4=Attack bit5=Jump
// bit6=Special(B3) bit7=Start bit8=Coin bit9=Pause/credits. Caveman Ninja
// reserves bit6 with a "-" placeholder, so START/COIN sit at bits 7/8 for BOTH.
// jtframe joystick: [6:4]={B3,B2,B1}, [3:0] dir nibble with
// JTFRAME_JOY_RLDU => {R,L,D,U} = {in[0],in[1],in[2],in[3]}.
function [6:0] jtjoy(input [31:0] m);
	jtjoy = ~{ m[6], m[5], m[4], m[0], m[1], m[2], m[3] };
endfunction

wire [6:0] joystick1 = jtjoy(joystick_0);
wire [6:0] joystick2 = jtjoy(joystick_1);
wire [6:0] joystick3 = jtjoy(joystick_2);
wire [6:0] joystick4 = jtjoy(joystick_3);

wire [3:0] cab_1p = ~{ joystick_3[7], joystick_2[7], joystick_1[7], joystick_0[7] };
wire [3:0] coin   = ~{ joystick_3[8], joystick_2[8], joystick_1[8], joystick_0[8] };
wire       game_pause = joystick_0[9] | joystick_1[9];

//////////////////////////////   GAME CORE   /////////////////////////////////
wire [7:0] red, green, blue;
wire       LHBL, LVBL, HS, VS;        // jtframe blanks are ACTIVE-LOW
wire       pxl_cen, pxl2_cen;
wire       dip_flip;

wire signed [15:0] snd;
wire         [5:0] snd_vu;
wire               snd_peak, sample;

// Board-facing SDRAM bus (muxed between the game and the debug dump engine).
wire [21:0] ba0_addr, ba1_addr, ba2_addr, ba3_addr;
wire  [3:0] ba_rd, ba_wr;
wire  [3:0] ba_dst, ba_dok, ba_rdy, ba_ack;
// Game-side SDRAM bus (before the debug mux).
wire [21:0] g_ba0_addr, g_ba1_addr, g_ba2_addr, g_ba3_addr;
wire  [3:0] g_ba_rd, g_ba_wr;
wire [15:0] ba0_din, ba1_din, ba2_din, ba3_din;
wire  [1:0] ba0_dsn, ba1_dsn, ba2_dsn, ba3_dsn;
wire [15:0] data_read;
wire [15:0] prog_data;
wire  [1:0] prog_ba, prog_mask;
wire [21:0] prog_addr;
wire        prog_rd, prog_rdy, prog_dst, prog_dok;

jtframe_pxlcen u_pxlcen(
	.clk      ( clk48    ),
	.pxl_cen  ( pxl_cen  ),
	.pxl2_cen ( pxl2_cen )
);

jtcninja_game_sdram u_game
(
	.rst        ( rst48     ),
	.clk        ( clk48     ),
	.rst24      ( rst24     ),
	.clk24      ( clk24     ),
	.rst96      ( rst96     ),
	.clk96      ( clk96     ),

	.pxl2_cen   ( pxl2_cen  ),
	.pxl_cen    ( pxl_cen   ),
	.red        ( red       ),
	.green      ( green     ),
	.blue       ( blue      ),
	.LHBL       ( LHBL      ),
	.LVBL       ( LVBL      ),
	.HS         ( HS        ),
	.VS         ( VS        ),

	.cab_1p     ( cab_1p    ),
	.coin       ( coin      ),
	.joystick1  ( joystick1 ),
	.joystick2  ( joystick2 ),
	.joystick3  ( joystick3 ),
	.joystick4  ( joystick4 ),
	.dial_x     ( 2'd0      ),
	.dial_y     ( 2'd0      ),
	.joyana_l1  ( 16'd0 ), .joyana_l2 ( 16'd0 ), .joyana_l3 ( 16'd0 ), .joyana_l4 ( 16'd0 ),
	.joyana_r1  ( 16'd0 ), .joyana_r2 ( 16'd0 ), .joyana_r3 ( 16'd0 ), .joyana_r4 ( 16'd0 ),

	.snd_en     ( 6'h3f     ),
	.snd_vol    ( 8'hff     ),

	.status     ( status[31:0] ),
	.dipsw      ( dipsw     ),
	.dip_pause  ( game_pause ? 1'b0 : 1'b1 ),
	.dip_test   ( 1'b1      ),
	.service    ( 1'b1      ),
	.tilt       ( 1'b1      ),
	.dip_flip   ( dip_flip  ),
	.dip_fxlevel( 2'b11     ),

	.st_addr    ( 8'd0      ),
	.st_dout    (           ),
	.gfx_en     ( 4'hf      ),
	.debug_bus  ( 8'd0      ),
	.debug_view (           ),

	.ioctl_addr ( ioctl_addr[25:0] ),
	.ioctl_dout ( ioctl_dout ),
	.ioctl_wr   ( ioctl_wr  ),
	.ioctl_rom  ( ioctl_rom ),
	.ioctl_ram  ( 1'b0      ),
	.ioctl_cart ( 1'b0      ),
	.dwnld_busy ( dwnld_busy ),
	.data_read  ( data_read ),

	.ba0_addr ( g_ba0_addr ), .ba1_addr ( g_ba1_addr ), .ba2_addr ( g_ba2_addr ), .ba3_addr ( g_ba3_addr ),
	.ba_rd    ( g_ba_rd    ), .ba_wr    ( g_ba_wr    ),
	.ba_dst   ( ba_dst   ), .ba_dok   ( ba_dok   ), .ba_rdy ( ba_rdy ), .ba_ack ( ba_ack ),
	.ba0_din  ( ba0_din  ), .ba1_din  ( ba1_din  ), .ba2_din ( ba2_din ), .ba3_din ( ba3_din ),
	.ba0_dsn  ( ba0_dsn  ), .ba1_dsn  ( ba1_dsn  ), .ba2_dsn ( ba2_dsn ), .ba3_dsn ( ba3_dsn ),

	.prog_data ( prog_data ),
	.prog_rdy  ( prog_rdy  ),
	.prog_ack  ( prog_ack  ),
	.prog_dst  ( prog_dst  ),
	.prog_dok  ( prog_dok  ),
	.prog_ba   ( prog_ba   ),
	.prog_we   ( prog_we   ),
	.prog_rd   ( prog_rd   ),
	.prog_mask ( prog_mask ),
	.prog_addr ( prog_addr ),

	.snd        ( snd      ),
	.snd_vu     ( snd_vu   ),
	.snd_peak   ( snd_peak ),
	.sample     ( sample   )
);

assign ba0_addr = g_ba0_addr;
assign ba1_addr = g_ba1_addr;
assign ba2_addr = g_ba2_addr;
assign ba3_addr = g_ba3_addr;
assign ba_rd    = g_ba_rd;
assign ba_wr    = g_ba_wr;

//////////////////////////////   SDRAM   /////////////////////////////////////
jtframe_board_sdram #(.SDRAMW(22), .MISTER(1)) u_sdram
(
	.rst        ( rst_sd     ),
	.clk        ( clk48      ),
	.init       ( sdram_init ),
	.prog_en    ( dwnld_busy ),

	.ba0_addr   ( ba0_addr   ),
	.ba1_addr   ( ba1_addr   ),
	.ba2_addr   ( ba2_addr   ),
	.ba3_addr   ( ba3_addr   ),
	.burst_addr ( 22'd0      ),
	.burst_ba   ( 2'd0       ),
	.burst_rd   ( 1'b0       ),
	.burst_wr   ( 1'b0       ),
	.ba_rd      ( ba_rd      ),
	.ba_wr      ( ba_wr      ),
	.ba0_din    ( ba0_din    ), .ba0_dsn ( ba0_dsn ),
	.ba1_din    ( ba1_din    ), .ba1_dsn ( ba1_dsn ),
	.ba2_din    ( ba2_din    ), .ba2_dsn ( ba2_dsn ),
	.ba3_din    ( ba3_din    ), .ba3_dsn ( ba3_dsn ),
	.burst_din  ( 16'd0      ),
	.burst_ack  (            ),
	.burst_rdy  (            ),
	.burst_dst  (            ),
	.burst_dok  (            ),
	.ba_ack     ( ba_ack     ),
	.ba_rdy     ( ba_rdy     ),
	.ba_dst     ( ba_dst     ),
	.ba_dok     ( ba_dok     ),
	.dout       ( data_read  ),

	.prog_addr  ( prog_addr  ),
	.prog_data  ( prog_data  ),
	.prog_dsn   ( prog_mask  ),
	.prog_ba    ( prog_ba    ),
	.prog_we    ( prog_we    ),
	.prog_rd    ( prog_rd    ),
	.prog_dok   ( prog_dok   ),
	.prog_rdy   ( prog_rdy   ),
	.prog_dst   ( prog_dst   ),
	.prog_ack   ( prog_ack   ),

	.sdram_dq   ( SDRAM_DQ   ),
	.sdram_a    ( SDRAM_A    ),
	.sdram_dqml ( SDRAM_DQML ),
	.sdram_dqmh ( SDRAM_DQMH ),
	.sdram_nwe  ( SDRAM_nWE  ),
	.sdram_ncas ( SDRAM_nCAS ),
	.sdram_nras ( SDRAM_nRAS ),
	.sdram_ncs  ( SDRAM_nCS  ),
	.sdram_ba   ( SDRAM_BA   ),
	.sdram_cke  ( SDRAM_CKE  )
);

//////////////////////////////   VIDEO   /////////////////////////////////////
wire [23:0] game_rgb = { red, green, blue };

// ---- analog video adjustments (OSD) -------------------------------------
// H/V position: shift the HSync/VSync relative to the active window with
// jtframe_resync (same proven pattern as Arcade-TaitoF2). Signed 4-bit
// offsets (-8..+7); negate to make "positive = right/down" like the OSD list.
wire signed [4:0] hoffset = status[39:35];
wire signed [4:0] voffset = status[44:40];
wire resync_hs, resync_vs;
jtframe_resync #(.BITS(5)) u_resync
(
	.clk     ( clk48     ),
	.pxl_cen ( pxl_cen   ),
	.hs_in   ( HS        ),
	.vs_in   ( VS        ),
	.LVBL    ( LVBL      ),
	.LHBL    ( LHBL      ),
	.hoffset ( -hoffset  ),
	.voffset ( -voffset  ),
	.hs_out  ( resync_hs ),
	.vs_out  ( resync_vs )
);

// arcade_video drives INTERNAL wires so the analog H-Size stretch can be
// inserted at the emu output boundary (below) without any sys_top edits.
wire        av_ce, av_hs, av_vs, av_de;
wire [23:0] av_rgb;
wire [ 1:0] av_sl;

// jtframe LHBL/LVBL are active-low; arcade_video wants active-high HBlank/VBlank.
arcade_video #(.WIDTH(256), .DW(24)) u_arcade_video
(
	.clk_video          ( clk48           ),
	.ce_pix             ( pxl_cen         ),

	.RGB_in             ( game_rgb        ),
	.HBlank             ( ~LHBL           ),
	.VBlank             ( ~LVBL           ),
	.HSync              ( resync_hs       ),
	.VSync              ( resync_vs       ),

	.CLK_VIDEO          (                 ),
	.CE_PIXEL           ( av_ce           ),
	.VGA_R              ( av_rgb[23:16]   ),
	.VGA_G              ( av_rgb[15:8]    ),
	.VGA_B              ( av_rgb[7:0]     ),
	.VGA_HS             ( av_hs           ),
	.VGA_VS             ( av_vs           ),
	.VGA_DE             ( av_de           ),
	.VGA_SL             ( av_sl           ),

	.fx                 ( status[5:3]     ),
	.forced_scandoubler ( forced_scandoubler ),
	.gamma_bus          ( gamma_bus       )
);

// ---- Analog H-Size (experimental, NO sys_top edits) ---------------------
// Stretch each pixel on the ANALOG path by holding it for more CLK_VIDEO
// cycles: read the arcade_video stream out slightly slower than it arrived via
// the analog_hsize elastic FIFO, and slow CE_PIXEL to match. The analog DAC in
// sys_top reproduces pixel DURATION literally -> wider pixels; the HDMI scaler
// normalizes active-to-fit -> HDMI is unaffected. One emu output stream thus
// yields stretched analog + clean HDMI with the framework untouched.
//
// Re-timed on clk96 (16x pixel) for 6.25%/step instead of 12.5%: native pixel
// = 8 clk48 = 16 clk96 (JTFRAME_PXLCLK=6 -> 6 MHz), so base 16 is exact. clk96
// is 2x clk48 from the same PLL (synchronous), so arcade_video's clk48-domain
// outputs are sampled safely on clk96. base 16 assumes scandoubler OFF (the
// analog/CRT case); with it ON av_ce is faster -> over-stretch. EXPERIMENTAL.
wire [2:0] hsize_amt = status[34:32];

// av_ce (clk48 pixel enable) -> single clk96 write pulse
reg  av_ce_d;
always @(posedge clk96) av_ce_d <= av_ce;
wire av_wr = av_ce & ~av_ce_d;

// HSync rising (sampled on clk96) locks the read phase per line
reg  av_hs_d;
always @(posedge clk96) av_hs_d <= av_hs;
wire av_hs_rise = av_hs & ~av_hs_d;

// read enable: one pulse every (16 + hsize) clk96 cycles
reg  [4:0] hsize_div;
wire [4:0] hsize_max = 5'd15 + {2'd0, hsize_amt};   // base 16 (+hsize)
always @(posedge clk96) begin
	if (av_hs_rise || hsize_div == hsize_max) hsize_div <= 5'd0;
	else                                      hsize_div <= hsize_div + 5'd1;
end
wire              str_ce  = (hsize_amt == 3'd0) ? av_wr : (hsize_div == 5'd0);
wire signed [3:0] hsize_s = -$signed({1'b0, hsize_amt});  // module: 0 bypass, <0 wider

// Left-anchored stretch: the module grows the active rightward into the front
// porch. Recenter (and gain headroom) by hand with the Analog Video H-Pos OSD
// offset -- it shifts the HSync feeding this module (via jtframe_resync upstream),
// which is exactly what an auto-recenter would do, so no extra logic is needed.
wire [23:0] str_rgb;
wire        str_hs, str_vs, str_hb, str_vb;
analog_hsize u_analog_hsize
(
	.clk     ( clk96          ),
	.pxl_cen ( av_wr          ),
	.pxl2_cen( str_ce         ),
	.hsize   ( hsize_s        ),
	.r_in    ( av_rgb[23:16]  ),
	.g_in    ( av_rgb[15:8]   ),
	.b_in    ( av_rgb[7:0]    ),
	.hs_in   ( av_hs          ),
	.vs_in   ( av_vs          ),
	.hb_in   ( ~av_de         ),
	// vb_in must NOT carry the horizontal blank: av_de is the COMBINED active
	// (~(hbl|vbl)), so feeding ~av_de here makes vb_out rise at the original
	// active-end and re-clamps the output DE to the original width (clipping the
	// stretched tail). Vertical blank is already covered by hb_out (no pixels are
	// pushed on vblank lines -> hb_out stays high -> DE low), so tie vb_in low.
	.vb_in   ( 1'b0           ),
	.r_out   ( str_rgb[23:16] ),
	.g_out   ( str_rgb[15:8]  ),
	.b_out   ( str_rgb[7:0]   ),
	.hs_out  ( str_hs         ),
	.vs_out  ( str_vs         ),
	.hb_out  ( str_hb         ),
	.vb_out  ( str_vb         )
);

assign CLK_VIDEO = clk96;
assign CE_PIXEL  = str_ce;
assign VGA_R     = str_rgb[23:16];
assign VGA_G     = str_rgb[15:8];
assign VGA_B     = str_rgb[7:0];
assign VGA_HS    = str_hs;
assign VGA_VS    = str_vs;
assign VGA_DE    = ~str_hb & ~str_vb;
assign VGA_SL    = av_sl;

assign LED_USER = dwnld_busy;

//////////////////////////////   AUDIO   /////////////////////////////////////
assign AUDIO_L = snd;
assign AUDIO_R = snd;
assign AUDIO_S = 1'b1;   // signed samples

endmodule

//----------------------------------------------------------------------------
// Async-assert / sync-deassert active-high reset synchronizer.
//----------------------------------------------------------------------------
module sync_rst(input clk, input arst, output reg rst);
	reg r;
	always @(posedge clk or posedge arst)
		if (arst) {rst, r} <= 2'b11;
		else      {rst, r} <= {r, 1'b0};
endmodule
