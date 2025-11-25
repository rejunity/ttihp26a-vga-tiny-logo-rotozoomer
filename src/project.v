/*
 * Copyright (c) 2025 Renaldas Zioma
 * SPDX-License-Identifier: Apache-2.0
 */


`default_nettype none

// module tt_um_vga_example(
module tt_um_rejunity_vga_logo (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
  // Suppress unused signals warning
  wire _unused_ok = &{ena, ui_in[7:3], uio_in};

  // VGA signals
  wire hsync;
  wire vsync;
  wire [1:0] R;
  wire [1:0] G;
  wire [1:0] B;

  // TinyVGA PMOD
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  // Unused outputs assigned to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;

  wire [9:0] x_px;
  wire [9:0] y_px;
  wire activevideo;
  
  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(activevideo),
    .hpos(x_px),
    .vpos(y_px)
  );

  wire signed [31:0] sin_t;
  wire signed [31:0] cos_t;
  
  sine_rom_16_16 sin_lut (
      .addr(sin_addr),
      .data(sin_t)
  );

  sine_rom_16_16 cos_lut (
      .addr(cos_addr),
      .data(cos_t)
  );

  wire [7:0] sin_addr = frame[6:0];
  wire [7:0] cos_addr = frame[6:0]+128;

  reg signed [31:0] sin_x_acc;
  reg signed [31:0] cos_x_acc;
  reg signed [31:0] sin_y_acc;
  reg signed [31:0] cos_y_acc;
  always @(posedge clk) begin
    if (x_px == 0 && y_px == 0) begin
      sin_x_acc <= 0;
      cos_x_acc <= 0;
      sin_y_acc <= 0;
      cos_y_acc <= 0;
    end else if (x_px == 0) begin
      sin_x_acc <= 0;
      cos_x_acc <= 0;
      sin_y_acc <= sin_y_acc + sin_t[0+:16];
      cos_y_acc <= cos_y_acc + cos_t[0+:16];
    end else begin
      sin_x_acc <= sin_x_acc + sin_t[0+:16];
      cos_x_acc <= cos_x_acc + cos_t[0+:16];
    end
  end

  // wire signed [10:0] x = x_px;
  // wire signed [10:0] y = y_px;
  // wire signed [63:0] x_mul_cos = cos_t[0+:16] * x - sin_t[0+:16] * y;
  // wire signed [63:0] y_mul_sin = sin_t[0+:16] * x + cos_t[0+:16] * y;
  // wire signed [63:0] x_px_ = x_mul_cos[14+:9];
  // wire signed [63:0] y_px_ = y_mul_sin[14+:9];

  wire signed [10:0] rotated_x = (cos_x_acc - sin_y_acc)>>13;
  wire signed [10:0] rotated_y = (sin_x_acc + cos_y_acc)>>13;
  wire               rotated_checkers = rotated_x[10] ^ rotated_y[10];

  wire [31:0] diagonals = cos_x_acc - sin_y_acc - sin_x_acc - cos_y_acc;
  wire [17:0] diagonalsZ = (diagonals[9+:18] << 1) ^ (diagonals[9+:18] >> 1);
  wire [17:0] rotated_bg = diagonalsZ;

  wire logo;
  tt_logo tt_logo(
    .x(rotated_x[9:1]+64),
    .y(rotated_y[9:1]-8),
    .logo(logo)
  );

  reg [9:0] y_prv;
  reg [10:0] frame;
  always @(posedge clk) begin
    if (~rst_n) begin
      frame <= 0;
    end else begin
      y_prv <= y_px;
      if (y_px == 0 && y_prv != y_px) begin
          frame <= frame + 1;
      end
    end
  end

  // Bayer dithering
  // this is a 8x4 Bayer matrix which gets toggled every frame (so the other 8x4 elements are actually on odd frames)
  wire [2:0] bayer_i = x_px[2:0] ^ {3{frame[0]}};
  wire [1:0] bayer_j = y_px[1:0];
  wire [2:0] bayer_x = {bayer_i[2], bayer_i[1]^bayer_j[1], bayer_i[0]^bayer_j[0]};
  wire [4:0] bayer   = {bayer_x[0], bayer_i[0], bayer_x[1], bayer_i[1], bayer_x[2]};

  // output dithered 2 bit color from 6 bit color and 5 bit Bayer matrix
  function [1:0] dither2;
    input [5:0] color6;
    input [4:0] bayer5;
    begin
      dither2 = ({1'b0, color6} + {2'b0, bayer5} + color6[0] + color6[5] + color6[5:1]) >> 5;
    end
  endfunction

  wire [1:0] r_dither = dither2(r, bayer);
  wire [1:0] g_dither = dither2(g, bayer);
  wire [1:0] b_dither = dither2(b, bayer);

  function [17:0] rgb18;
    input [5:0] rgb6;
    begin
      rgb18 = {rgb6[5:4], 4'b0, rgb6[3:2], 4'b0, rgb6[1:0], 4'b0};
    end 
  endfunction

  function signed [17:0] rgb18_add;
    input signed [17:0] rgb0;
    input signed [17:0] rgb1;
    begin
      rgb18_add = {rgb0[17:11] + rgb1[17:11],
                   rgb0[10: 6] + rgb1[10: 6],
                   rgb0[ 5: 0] + rgb1[ 5: 0]};
    end 
  endfunction
  
  wire [5:0] r, g, b;
  assign {r, g, b} = logo ? (rotated_checkers ? rgb18(63):rgb18(63-3)) :
                            {18{rotated_checkers}} & rotated_bg;

  assign {R, G, B} = 
    ~activevideo ? 0 : { r_dither, g_dither, b_dither };

  // TinyVGA PMOD
`ifdef VGA_REGISTERED_OUTPUTS
  reg [7:0] UO_OUT;
  always @(posedge clk)
    UO_OUT <= {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
  assign uo_out = UO_OUT;
`else
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
`endif
endmodule

module sine_rom_16_16 (
    input  wire [7:0] addr,       
    output reg  signed [31:0] data
);
  wire signed [31:0] half_data;
  sine_rom_16_16_half sin_lut (
      .addr(addr[6:0]),
      .data(half_data)
  );
  assign data = addr[7] ? half_data : 32'h0001_0000 - half_data;
endmodule

module sine_rom_16_16_half (
    input  wire [6:0] addr,       
    output reg  signed [31:0] data
);
  sine_rom_16_16_quart sin_lut (
      .addr(quart_addr),
      .data(data)
  );
  wire [5:0] quart_addr = addr[6] ? addr : 6'b111_111 - addr[5:0];
endmodule

module sine_rom_16_16_quart (
    input  wire [5:0] addr,       
    output reg  signed [31:0] data
);
    always @* begin
        case (addr)
            8'd0: data = 32'sh00000001; //        0 -> sin(0.0°)
            8'd1: data = 32'sh0000064F; //     1615 -> sin(1.411764705882353°)
            8'd2: data = 32'sh00000C9C; //     3228 -> sin(2.823529411764706°)
            8'd3: data = 32'sh000012E8; //     4840 -> sin(4.235294117647059°)
            8'd4: data = 32'sh00001931; //     6449 -> sin(5.647058823529412°)
            8'd5: data = 32'sh00001F76; //     8054 -> sin(7.058823529411765°)
            8'd6: data = 32'sh000025B6; //     9654 -> sin(8.470588235294118°)
            8'd7: data = 32'sh00002BF0; //    11248 -> sin(9.882352941176471°)
            8'd8: data = 32'sh00003223; //    12835 -> sin(11.294117647058824°)
            8'd9: data = 32'sh0000384E; //    14414 -> sin(12.705882352941178°)
            8'd10: data = 32'sh00003E71; //    15985 -> sin(14.11764705882353°)
            8'd11: data = 32'sh0000448A; //    17546 -> sin(15.529411764705884°)
            8'd12: data = 32'sh00004A99; //    19097 -> sin(16.941176470588236°)
            8'd13: data = 32'sh0000509B; //    20635 -> sin(18.35294117647059°)
            8'd14: data = 32'sh00005692; //    22162 -> sin(19.764705882352942°)
            8'd15: data = 32'sh00005C7A; //    23674 -> sin(21.176470588235297°)
            8'd16: data = 32'sh00006255; //    25173 -> sin(22.58823529411765°)
            8'd17: data = 32'sh00006820; //    26656 -> sin(24.0°)
            8'd18: data = 32'sh00006DDB; //    28123 -> sin(25.411764705882355°)
            8'd19: data = 32'sh00007385; //    29573 -> sin(26.823529411764707°)
            8'd20: data = 32'sh0000791D; //    31005 -> sin(28.23529411764706°)
            8'd21: data = 32'sh00007EA2; //    32418 -> sin(29.647058823529413°)
            8'd22: data = 32'sh00008413; //    33811 -> sin(31.058823529411768°)
            8'd23: data = 32'sh00008970; //    35184 -> sin(32.47058823529412°)
            8'd24: data = 32'sh00008EB8; //    36536 -> sin(33.88235294117647°)
            8'd25: data = 32'sh000093E9; //    37865 -> sin(35.294117647058826°)
            8'd26: data = 32'sh00009903; //    39171 -> sin(36.70588235294118°)
            8'd27: data = 32'sh00009E06; //    40454 -> sin(38.11764705882353°)
            8'd28: data = 32'sh0000A2F0; //    41712 -> sin(39.529411764705884°)
            8'd29: data = 32'sh0000A7C1; //    42945 -> sin(40.94117647058824°)
            8'd30: data = 32'sh0000AC77; //    44151 -> sin(42.352941176470594°)
            8'd31: data = 32'sh0000B113; //    45331 -> sin(43.76470588235294°)
            8'd32: data = 32'sh0000B593; //    46483 -> sin(45.1764705882353°)
            8'd33: data = 32'sh0000B9F8; //    47608 -> sin(46.58823529411765°)
            8'd34: data = 32'sh0000BE3F; //    48703 -> sin(48.0°)
            8'd35: data = 32'sh0000C268; //    49768 -> sin(49.411764705882355°)
            8'd36: data = 32'sh0000C674; //    50804 -> sin(50.82352941176471°)
            8'd37: data = 32'sh0000CA60; //    51808 -> sin(52.235294117647065°)
            8'd38: data = 32'sh0000CE2D; //    52781 -> sin(53.64705882352941°)
            8'd39: data = 32'sh0000D1DB; //    53723 -> sin(55.05882352941177°)
            8'd40: data = 32'sh0000D567; //    54631 -> sin(56.47058823529412°)
            8'd41: data = 32'sh0000D8D2; //    55506 -> sin(57.88235294117647°)
            8'd42: data = 32'sh0000DC1C; //    56348 -> sin(59.294117647058826°)
            8'd43: data = 32'sh0000DF43; //    57155 -> sin(60.70588235294118°)
            8'd44: data = 32'sh0000E248; //    57928 -> sin(62.117647058823536°)
            8'd45: data = 32'sh0000E529; //    58665 -> sin(63.529411764705884°)
            8'd46: data = 32'sh0000E7E7; //    59367 -> sin(64.94117647058825°)
            8'd47: data = 32'sh0000EA81; //    60033 -> sin(66.3529411764706°)
            8'd48: data = 32'sh0000ECF7; //    60663 -> sin(67.76470588235294°)
            8'd49: data = 32'sh0000EF47; //    61255 -> sin(69.1764705882353°)
            8'd50: data = 32'sh0000F173; //    61811 -> sin(70.58823529411765°)
            8'd51: data = 32'sh0000F378; //    62328 -> sin(72.0°)
            8'd52: data = 32'sh0000F558; //    62808 -> sin(73.41176470588236°)
            8'd53: data = 32'sh0000F712; //    63250 -> sin(74.82352941176471°)
            8'd54: data = 32'sh0000F8A6; //    63654 -> sin(76.23529411764706°)
            8'd55: data = 32'sh0000FA13; //    64019 -> sin(77.64705882352942°)
            8'd56: data = 32'sh0000FB59; //    64345 -> sin(79.05882352941177°)
            8'd57: data = 32'sh0000FC78; //    64632 -> sin(80.47058823529412°)
            8'd58: data = 32'sh0000FD6F; //    64879 -> sin(81.88235294117648°)
            8'd59: data = 32'sh0000FE40; //    65088 -> sin(83.29411764705883°)
            8'd60: data = 32'sh0000FEE8; //    65256 -> sin(84.70588235294119°)
            8'd61: data = 32'sh0000FF6A; //    65386 -> sin(86.11764705882354°)
            8'd62: data = 32'sh0000FFC3; //    65475 -> sin(87.52941176470588°)
            8'd63: data = 32'sh0000FFF5; //    65525 -> sin(88.94117647058825°)
            default: data = 32'sh00000000;
        endcase
    end
endmodule


// TODO: move into a separate logo.v file
module tt_logo(
  input wire [9:0] x,
  input wire [9:0] y,
  output wire logo
);
  wire signed [8:0] x_signed = $signed(x[8:0]);
  wire signed [8:0] y_signed = $signed(y[8:0]);

  //wire [17:0] sq0x_; approx_signed_square #(9,3,3) sq0x(.a(x_signed - 9'sd320), .p_approx(x_sq));
  wire [17:0] x_sq; approx_signed_square #(9,4,4) sq0x(.a(x_signed - 9'sd320), .p_approx(x_sq));
  wire [17:0] y_sq; approx_signed_square #(9,4,3) sq0y(.a(y_signed - 9'sd240), .p_approx(y_sq));

  wire _unused_ok = &{x_sq[17:16], y_sq[17:16]};

  wire [15:0] r_sq = x_sq[15:0] + y_sq[15:0];

  // wire ring = (rx+ry) < 240*240 & (rx+ry) > (240-36)*(240-36);
  wire ring = r_sq < 238*238 & r_sq > (238-36)*(238-36);

  // xy: 46x100 wh:240x64
  wire hat0 = x >= 80+46  & x < 80+46+240  & y >= 100 & y < 100+64;
  // xy:144x100 wh:70x228
  wire leg0 = x >= 80+144 & x < 80+144+70  & y >= 100 & y < 100+228;
  // xy:144x222 wh:254x64
  wire hat1 = x >= 80+144 & x < 80+144+254 & y >= 222 & y < 222+64;
  // xy:256x222 wh:70x240
  wire leg1 = x >= 80+256 & x < 80+256+70  & y >= 222 & y < 222+240;

  // xy:(256+70)x(222+64) wh:20x...
  wire cut0 = ~(x >= 80   & x < 80+144     & y >= 100+64 & y < 100+60+22);
  // xy:(256+70)x(222+64) wh:20x...
  wire cut1 = ~(x >= 80+256+70 & x < 80+256+70+22 & y >= 222+64 & y < 480);

  assign logo = (ring&cut0&cut1)|hat0|leg0|hat1|leg1;
endmodule

module approx_signed_square #(
    parameter integer W = 12,
    parameter integer T = 4,  // truncate this many LSBs
    parameter integer R = 3   // use top R bits of low part to approximate cross-term
)(
    input  wire signed [W-1:0] a,
    output wire [2*W-1:0] p_approx
);
    // -------------------------
    // Guards
    // -------------------------
    initial begin
        if (W <= 1)  $error("W must be >= 2");
        if (T < 0)   $error("T must be >= 0");
        if (T >= W)  $error("T must be <= W-1");
        if (R < 0)   $error("R must be >= 0");
        if (R > T)   $error("R must be <= T");
    end

    localparam integer H = W - T;                // width of high part
    localparam integer PROD_W_HH = 2*H;          // width of x_h^2
    localparam integer SHIFT_HH  = 2*T;          // alignment for x_h^2
    localparam integer SHIFT_X   = (2*T >= R) ? (2*T - R) : 0; // alignment for cross-term

    // -------------------------
    // Work with magnitude (unsigned) since a^2 is non-negative
    // -------------------------
    wire [W-1:0] x = a[W-1] ? (~a + 1'b1) : a;   // abs(a)

    // Partition (unsigned slices)
    wire [H-1:0] x_h = (T == 0) ? x[W-1:0] : x[W-1:T];
    wire [T-1:0] x_l = (T == 0) ? {T{1'b0}} : x[T-1:0];

    // Core: x_h^2 << (2T)
    wire [PROD_W_HH-1:0] prod_hh_u = x_h * x_h;
    wire [2*W-1:0] term_hh_u = {{(2*W-PROD_W_HH){1'b0}}, prod_hh_u} << SHIFT_HH;

    // Optional cross-term using only top R bits of x_l
    generate
        if (R == 0) begin : no_correction
            assign p_approx = $signed(term_hh_u); // pure truncation
        end else begin : with_correction
            // Top R bits of x_l (unsigned)
            wire [R-1:0] x_l_top = x_l[T-1 -: R];  // x_l >> (T-R), keeping R bits

            // One small multiplier: (H x R)
            wire [H+R-1:0] prod_hl_u = x_h * x_l_top;

            // Approximate 2*x_h*x_l << T  ≈  2*(x_h*x_l_top) << (2T - R)
            // "×2" is a left shift by 1
            wire [2*W-1:0] term_x_u =
                ({{(2*W-(H+R)){1'b0}}, prod_hl_u} << (SHIFT_X + 1));

            assign p_approx = $signed(term_hh_u + term_x_u);
            // assign p_approx = term_hh_u + term_x_u;
        end
    endgenerate

endmodule
