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
// DDRAM is driven by u_rotate (screen_rotate) for the vertical framebuffer.

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

wire [1:0] ar = status[14:13];
assign VIDEO_ARX = (!ar) ? (no_rotate ? 12'd4 : 12'd3) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (no_rotate ? 12'd3 : 12'd4) : 12'd0;

//////////////////////////////   CONF_STR   //////////////////////////////////
`include "build_id.v"
localparam CONF_STR = {
	"Arcade-Deco16;;",
	"-;",
	"P1,Video Settings;",
	"P1O[14:13],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O[2:1],Vertical rotation,Off,CW,CCW,Off;",
	"P1O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"P1-;",
	"P1O[32],CRT Adjust,Off,On;",
	"H1P1O[37:33],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[42:38],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H1P1O[47:43],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
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
	.status_menumask    ( {14'd0, ~status[32], 1'b0} ),  // H1: hide CRT amounts unless On
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

// game_id = MRA header byte 0 (JTFRAME_HEADER=16, same byte the core decodes to
// pick the address map). Latch it here so emu can rotate the vertical game.
reg  [3:0]  game_id = 4'd0;
always @(posedge clk48)
	if (ioctl_rom && ioctl_wr && ioctl_addr[25:0]==26'd0) game_id <= ioctl_dout[3:0];

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

// ---- CRT Adjust (core-side analog geometry, OSD-controlled) --------------
// crt_adjust shifts/resizes the picture CONTENT through a line buffer while the
// native HSync/VSync pass through untouched, so a real CRT never loses lock.
// Three controls, all live only while CRT Adjust is On:
//   H-Size     : horizontal stretch/squeeze (read rate vs write rate)
//   H-Position : horizontal content shift    (read address offset, sync intact)
//   V-Shift    : vertical line shift          (VSync delayed N lines)
// Inserted BEFORE arcade_video: the module runs at the native 6 MHz pixel rate;
// arcade_video's scandoubler/mixer then runs off the read clock-enable. Replaces
// the old jtframe_resync H/V-Pos, which moved the sync (and whose analog H-Size
// half always needed a sys_top edit — this content-shift variant needs none).
wire crt_on = status[32];

// Decode signed 5-bit OSD amounts (0, +1..+15, -16..-1).
wire signed [4:0] hsize_s  = $signed(status[37:33]);
wire signed [4:0] hpos_s   = $signed(status[42:38]);
wire signed [5:0] vshift_s = $signed(status[47:43]);
wire signed [8:0] hpos_off = hpos_s;   // sign-extend to the module's 9-bit H-Position

// Read clock-enable: one pixel every (32 + hsize) QUARTER-cycles of clk48
// (base 32 = 8 whole cycles = the native 6 MHz pixel; each H-Size step ~3%).
// Reset the accumulator on the NATIVE HSync rise -> deterministic per-line phase.
reg  HS_d;
always @(posedge clk48) HS_d <= HS;
wire native_hs_rise = HS & ~HS_d;

wire [7:0] rd_period = 8'd32 + {{3{hsize_s[4]}}, hsize_s};   // -16..+15 -> 16..47
reg  [7:0] rd_acc;
wire       rd_tick = (rd_acc + 8'd4) >= {1'b0, rd_period};
always @(posedge clk48) begin
	if      (native_hs_rise) rd_acc <= 8'd0;
	else if (rd_tick)        rd_acc <= rd_acc + 8'd4 - {1'b0, rd_period};
	else                     rd_acc <= rd_acc + 8'd4;
end
wire rd_ce = crt_on ? rd_tick : pxl_cen;

// The module: fed the NATIVE sync (keeps the CRT locked) and the TRUE vertical
// blank on vb_in (so the downstream OSD keeps a valid vertical frame boundary).
wire [7:0] str_r, str_g, str_b;
wire       str_hs, str_vs, str_hb, str_vb;
crt_adjust #(.VTOTAL(274)) u_crt_adjust
(
	.clk      ( clk48         ),
	.pxl_cen  ( pxl_cen       ),        // write rate (native 6 MHz pixel)
	.pxl2_cen ( rd_ce         ),        // read rate  (H-Size)
	.active   ( crt_on        ),
	.hsize    ( hsize_s       ),
	.hoffset  ( hpos_off      ),
	.voffset  ( vshift_s      ),
	.r_in     ( red           ),
	.g_in     ( green         ),
	.b_in     ( blue          ),
	.hs_in    ( HS            ),        // NATIVE HSync -> no desync
	.vs_in    ( VS            ),
	.hb_in    ( ~LHBL | ~LVBL ),        // combined blank
	.vb_in    ( ~LVBL         ),        // true vertical blank
	.r_out    ( str_r         ),
	.g_out    ( str_g         ),
	.b_out    ( str_b         ),
	.hs_out   ( str_hs        ),
	.vs_out   ( str_vs        ),
	.hb_out   ( str_hb        ),
	.vb_out   ( str_vb        )
);

// Keep the OSD PUT: the MiSTer OSD centers on the RISING edge of VGA_DE. Build a
// DE window whose rising is anchored to the NATIVE active region and whose
// falling follows the stretched active's end, so H-Position slides the image
// without dragging the OSD. Fed to arcade_video as its (active-low) HBlank; it
// already drops during VBlank, so arcade_video's VBlank is tied low then.
reg  lvbl_1l;
always @(posedge clk48) if (native_hs_rise) lvbl_1l <= LVBL;   // per-line vertical-visible
wire native_active = LHBL & lvbl_1l;
reg  native_active_d;
always @(posedge clk48) if (pxl_cen) native_active_d <= native_active;
wire native_rise = native_active & ~native_active_d;

wire str_active = ~str_hb;
reg  str_active_d;
always @(posedge clk48) if (rd_ce) str_active_d <= str_active;
wire str_fall = str_active_d & ~str_active;

reg de_osd;
always @(posedge clk48) begin
	if      (native_rise) de_osd <= 1'b1;
	else if (str_fall)    de_osd <= 1'b0;
end

// Mux: CRT Adjust On -> module outputs at the read rate; Off -> native
// passthrough (bit-identical to no module). jtframe LHBL/LVBL are active-low;
// arcade_video wants active-high HBlank/VBlank.
wire        av_ce  = crt_on ? rd_ce                 : pxl_cen;
wire [23:0] av_rgb = crt_on ? {str_r, str_g, str_b} : game_rgb;
wire        av_hb  = crt_on ? ~de_osd               : ~LHBL;
wire        av_vb  = crt_on ? 1'b0                  : ~LVBL;
wire        av_hs  = crt_on ? str_hs                : HS;
wire        av_vs  = crt_on ? str_vs                : VS;

arcade_video #(.WIDTH(256), .DW(24)) u_arcade_video
(
	.clk_video          ( clk48           ),
	.ce_pix             ( av_ce           ),

	.RGB_in             ( av_rgb          ),
	.HBlank             ( av_hb           ),
	.VBlank             ( av_vb           ),
	.HSync              ( av_hs           ),
	.VSync              ( av_vs           ),

	.CLK_VIDEO          ( CLK_VIDEO       ),
	.CE_PIXEL           ( CE_PIXEL        ),
	.VGA_R              ( VGA_R           ),
	.VGA_G              ( VGA_G           ),
	.VGA_B              ( VGA_B           ),
	.VGA_HS             ( VGA_HS          ),
	.VGA_VS             ( VGA_VS          ),
	.VGA_DE             ( VGA_DE          ),
	.VGA_SL             ( VGA_SL          ),

	.fx                 ( status[5:3]     ),
	.forced_scandoubler ( forced_scandoubler ),
	.gamma_bus          ( gamma_bus       )
);

// ---- rotation (vertical games) ------------------------------------------
wire [1:0] rot_mode = status[2:1];       // 0/3=off, 1=CW, 2=CCW
wire vertical   = (game_id == 4'd3);
wire rot_cw     = (rot_mode == 2'd1);
wire rot_ccw    = (rot_mode == 2'd2);
wire no_rotate  = ~(vertical & (rot_cw | rot_ccw) & ~direct_video);
wire rotate_ccw = rot_ccw;
wire video_rotated;

assign FB_FORCE_BLANK = 1'b0;

screen_rotate u_rotate
(
	.CLK_VIDEO      ( CLK_VIDEO      ),
	.CE_PIXEL       ( CE_PIXEL       ),
	.VGA_R          ( VGA_R          ),
	.VGA_G          ( VGA_G          ),
	.VGA_B          ( VGA_B          ),
	.VGA_HS         ( VGA_HS         ),
	.VGA_VS         ( VGA_VS         ),
	.VGA_DE         ( VGA_DE         ),

	.rotate_ccw     ( rotate_ccw     ),
	.no_rotate      ( no_rotate      ),
	.flip           ( 1'b0           ),
	.video_rotated  ( video_rotated  ),

	.FB_EN          ( FB_EN          ),
	.FB_FORMAT      ( FB_FORMAT      ),
	.FB_WIDTH       ( FB_WIDTH       ),
	.FB_HEIGHT      ( FB_HEIGHT      ),
	.FB_BASE        ( FB_BASE        ),
	.FB_STRIDE      ( FB_STRIDE      ),
	.FB_VBL         ( FB_VBL         ),
	.FB_LL          ( FB_LL          ),

	.DDRAM_CLK      ( DDRAM_CLK      ),
	.DDRAM_BUSY     ( DDRAM_BUSY     ),
	.DDRAM_BURSTCNT ( DDRAM_BURSTCNT ),
	.DDRAM_ADDR     ( DDRAM_ADDR     ),
	.DDRAM_DIN      ( DDRAM_DIN      ),
	.DDRAM_BE       ( DDRAM_BE       ),
	.DDRAM_WE       ( DDRAM_WE       ),
	.DDRAM_RD       ( DDRAM_RD       )
);

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
