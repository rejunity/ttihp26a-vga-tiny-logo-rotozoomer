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
  // wire cmp = y_px < 240 ?
  //     (32'sh0001_0000 + cos_t)>>9 > y_px      :
  //     (32'sh0001_0000 + sin_t)>>9 > y_px - 240;

  wire [7:0] sin_addr = frame[7:0];
  wire [7:0] cos_addr = frame[7:0]+128;

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

  wire signed [10:0] x = x_px;
  wire signed [10:0] y = y_px;
  // wire signed [63:0] x_mul_cos = cos_t[0+:16] * x - sin_t[0+:16] * y;
  // wire signed [63:0] y_mul_sin = sin_t[0+:16] * x + cos_t[0+:16] * y;
  // wire signed [63:0] x_px_ = x_mul_cos[14+:9];
  // wire signed [63:0] y_px_ = y_mul_sin[14+:9];
  // // wire signed [63:0] x_px_ = x_mul_cos[14+:9];
  // wire signed [63:0] y_px_ = y_mul_sin[14+:9];
  // wire signed [63:0] x_px_ = x_px_r[15+:16];
  // wire signed [63:0] y_px_ = y_px_r[15+:16];

  // wire signed [63:0] x_px_ = x_px_acc[15+:16] - y_px_acc[15+:16];
  // wire signed [63:0] y_px_ = x_px_acc[15+:16] + y_px_acc[15+:16];

  wire signed [10:0] rotated_x = (cos_x_acc - sin_y_acc)>>13;
  wire signed [10:0] rotated_y = (sin_x_acc + cos_y_acc)>>13;
  wire               rotated_checkers = rotated_x[10] ^ rotated_y[10];

  // wire [18:0] rot_bg = (cos_x_acc - sin_y_acc)>>9;
  // wire [18:0] rot_bg = (sin_x_acc + cos_y_acc)>>9;
  wire [31:0] diagonals = cos_x_acc - sin_y_acc - sin_x_acc - cos_y_acc;
  wire [17:0] diagonalsZ = (diagonals[9+:18] << 1) ^ (diagonals[9+:18] >> 1);
  wire [17:0] rotated_bg = diagonalsZ & {18{rotated_checkers}};

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
  
  reg signed [17:0] bg_at_y0;
  reg signed [17:0] bg_at_x0;
  reg signed [17:0] bg;
  // wire signed  [17:0] bg_inc = {6'b000_000, 6'b111_111, 6'b000_001};
  wire signed [17:0] bg_inc = $signed({{5'b000_00, ~ui_in[2]} , 6'b111_111, 6'b000_001});
  always @(posedge clk) begin
    if (~rst_n) begin
      bg_at_y0 <= bg_inc*640;
      bg_at_x0 <= 0;
      bg <= 0;
    end else
    if (x_px == 0) begin
      if (y_px == 0) begin
        bg_at_x0 <= bg_inc*640 + bg_at_y0;
        bg_at_y0 <= rgb18_add(bg_at_y0, -bg_inc*(ui_in[1:0] + 3'b1));
      end else begin
        bg_at_x0 <= rgb18_add(bg_at_x0, bg_inc);
        bg <= bg_at_x0;
      end
    end else begin
      bg <= rgb18_add(bg, bg_inc);
    end
  end

  wire [5:0] r, g, b;
  // assign {r, g, b} = logo ? rgb18(63-2) : rotated_bg;
  assign {r, g, b} = logo ? (rotated_checkers ? rgb18(63):rgb18(63-3)) : rotated_bg;

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

    always @* begin
        case (addr)
            8'd0: data = 32'sh00000000; //        0 -> sin(0.0°)
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
            8'd64: data = 32'sh0000FFFF; //    65535 -> sin(90.3529411764706°)
            8'd65: data = 32'sh0000FFE1; //    65505 -> sin(91.76470588235294°)
            8'd66: data = 32'sh0000FF9B; //    65435 -> sin(93.1764705882353°)
            8'd67: data = 32'sh0000FF2E; //    65326 -> sin(94.58823529411765°)
            8'd68: data = 32'sh0000FE99; //    65177 -> sin(96.0°)
            8'd69: data = 32'sh0000FDDC; //    64988 -> sin(97.41176470588236°)
            8'd70: data = 32'sh0000FCF8; //    64760 -> sin(98.82352941176471°)
            8'd71: data = 32'sh0000FBED; //    64493 -> sin(100.23529411764707°)
            8'd72: data = 32'sh0000FABB; //    64187 -> sin(101.64705882352942°)
            8'd73: data = 32'sh0000F961; //    63841 -> sin(103.05882352941177°)
            8'd74: data = 32'sh0000F7E1; //    63457 -> sin(104.47058823529413°)
            8'd75: data = 32'sh0000F63A; //    63034 -> sin(105.88235294117648°)
            8'd76: data = 32'sh0000F46D; //    62573 -> sin(107.29411764705883°)
            8'd77: data = 32'sh0000F27A; //    62074 -> sin(108.70588235294119°)
            8'd78: data = 32'sh0000F062; //    61538 -> sin(110.11764705882354°)
            8'd79: data = 32'sh0000EE24; //    60964 -> sin(111.52941176470588°)
            8'd80: data = 32'sh0000EBC0; //    60352 -> sin(112.94117647058825°)
            8'd81: data = 32'sh0000E939; //    59705 -> sin(114.3529411764706°)
            8'd82: data = 32'sh0000E68D; //    59021 -> sin(115.76470588235294°)
            8'd83: data = 32'sh0000E3BD; //    58301 -> sin(117.1764705882353°)
            8'd84: data = 32'sh0000E0CA; //    57546 -> sin(118.58823529411765°)
            8'd85: data = 32'sh0000DDB4; //    56756 -> sin(120.00000000000001°)
            8'd86: data = 32'sh0000DA7B; //    55931 -> sin(121.41176470588236°)
            8'd87: data = 32'sh0000D721; //    55073 -> sin(122.82352941176471°)
            8'd88: data = 32'sh0000D3A5; //    54181 -> sin(124.23529411764707°)
            8'd89: data = 32'sh0000D008; //    53256 -> sin(125.64705882352942°)
            8'd90: data = 32'sh0000CC4B; //    52299 -> sin(127.05882352941177°)
            8'd91: data = 32'sh0000C86E; //    51310 -> sin(128.47058823529412°)
            8'd92: data = 32'sh0000C472; //    50290 -> sin(129.8823529411765°)
            8'd93: data = 32'sh0000C057; //    49239 -> sin(131.29411764705884°)
            8'd94: data = 32'sh0000BC1F; //    48159 -> sin(132.7058823529412°)
            8'd95: data = 32'sh0000B7C9; //    47049 -> sin(134.11764705882354°)
            8'd96: data = 32'sh0000B357; //    45911 -> sin(135.52941176470588°)
            8'd97: data = 32'sh0000AEC9; //    44745 -> sin(136.94117647058823°)
            8'd98: data = 32'sh0000AA1F; //    43551 -> sin(138.3529411764706°)
            8'd99: data = 32'sh0000A55C; //    42332 -> sin(139.76470588235296°)
            8'd100: data = 32'sh0000A07E; //    41086 -> sin(141.1764705882353°)
            8'd101: data = 32'sh00009B88; //    39816 -> sin(142.58823529411765°)
            8'd102: data = 32'sh00009679; //    38521 -> sin(144.0°)
            8'd103: data = 32'sh00009153; //    37203 -> sin(145.41176470588238°)
            8'd104: data = 32'sh00008C17; //    35863 -> sin(146.82352941176472°)
            8'd105: data = 32'sh000086C4; //    34500 -> sin(148.23529411764707°)
            8'd106: data = 32'sh0000815D; //    33117 -> sin(149.64705882352942°)
            8'd107: data = 32'sh00007BE2; //    31714 -> sin(151.05882352941177°)
            8'd108: data = 32'sh00007653; //    30291 -> sin(152.47058823529412°)
            8'd109: data = 32'sh000070B2; //    28850 -> sin(153.8823529411765°)
            8'd110: data = 32'sh00006AFF; //    27391 -> sin(155.29411764705884°)
            8'd111: data = 32'sh0000653C; //    25916 -> sin(156.7058823529412°)
            8'd112: data = 32'sh00005F69; //    24425 -> sin(158.11764705882354°)
            8'd113: data = 32'sh00005988; //    22920 -> sin(159.52941176470588°)
            8'd114: data = 32'sh00005398; //    21400 -> sin(160.94117647058823°)
            8'd115: data = 32'sh00004D9B; //    19867 -> sin(162.3529411764706°)
            8'd116: data = 32'sh00004793; //    18323 -> sin(163.76470588235296°)
            8'd117: data = 32'sh0000417F; //    16767 -> sin(165.1764705882353°)
            8'd118: data = 32'sh00003B61; //    15201 -> sin(166.58823529411765°)
            8'd119: data = 32'sh0000353A; //    13626 -> sin(168.0°)
            8'd120: data = 32'sh00002F0A; //    12042 -> sin(169.41176470588238°)
            8'd121: data = 32'sh000028D3; //    10451 -> sin(170.82352941176472°)
            8'd122: data = 32'sh00002296; //     8854 -> sin(172.23529411764707°)
            8'd123: data = 32'sh00001C54; //     7252 -> sin(173.64705882352942°)
            8'd124: data = 32'sh0000160D; //     5645 -> sin(175.05882352941177°)
            8'd125: data = 32'sh00000FC2; //     4034 -> sin(176.47058823529412°)
            8'd126: data = 32'sh00000976; //     2422 -> sin(177.8823529411765°)
            8'd127: data = 32'sh00000327; //      807 -> sin(179.29411764705884°)
            8'd128: data = 32'shFFFFFCD9; //     -807 -> sin(180.7058823529412°)
            8'd129: data = 32'shFFFFF68A; //    -2422 -> sin(182.11764705882354°)
            8'd130: data = 32'shFFFFF03E; //    -4034 -> sin(183.52941176470588°)
            8'd131: data = 32'shFFFFE9F3; //    -5645 -> sin(184.94117647058826°)
            8'd132: data = 32'shFFFFE3AC; //    -7252 -> sin(186.3529411764706°)
            8'd133: data = 32'shFFFFDD6A; //    -8854 -> sin(187.76470588235296°)
            8'd134: data = 32'shFFFFD72D; //   -10451 -> sin(189.1764705882353°)
            8'd135: data = 32'shFFFFD0F6; //   -12042 -> sin(190.58823529411765°)
            8'd136: data = 32'shFFFFCAC6; //   -13626 -> sin(192.0°)
            8'd137: data = 32'shFFFFC49F; //   -15201 -> sin(193.41176470588238°)
            8'd138: data = 32'shFFFFBE81; //   -16767 -> sin(194.82352941176472°)
            8'd139: data = 32'shFFFFB86D; //   -18323 -> sin(196.23529411764707°)
            8'd140: data = 32'shFFFFB265; //   -19867 -> sin(197.64705882352942°)
            8'd141: data = 32'shFFFFAC68; //   -21400 -> sin(199.05882352941177°)
            8'd142: data = 32'shFFFFA678; //   -22920 -> sin(200.47058823529414°)
            8'd143: data = 32'shFFFFA097; //   -24425 -> sin(201.8823529411765°)
            8'd144: data = 32'shFFFF9AC4; //   -25916 -> sin(203.29411764705884°)
            8'd145: data = 32'shFFFF9501; //   -27391 -> sin(204.7058823529412°)
            8'd146: data = 32'shFFFF8F4E; //   -28850 -> sin(206.11764705882354°)
            8'd147: data = 32'shFFFF89AD; //   -30291 -> sin(207.52941176470588°)
            8'd148: data = 32'shFFFF841E; //   -31714 -> sin(208.94117647058826°)
            8'd149: data = 32'shFFFF7EA3; //   -33117 -> sin(210.3529411764706°)
            8'd150: data = 32'shFFFF793C; //   -34500 -> sin(211.76470588235296°)
            8'd151: data = 32'shFFFF73E9; //   -35863 -> sin(213.1764705882353°)
            8'd152: data = 32'shFFFF6EAD; //   -37203 -> sin(214.58823529411765°)
            8'd153: data = 32'shFFFF6987; //   -38521 -> sin(216.0°)
            8'd154: data = 32'shFFFF6478; //   -39816 -> sin(217.41176470588238°)
            8'd155: data = 32'shFFFF5F82; //   -41086 -> sin(218.82352941176472°)
            8'd156: data = 32'shFFFF5AA4; //   -42332 -> sin(220.23529411764707°)
            8'd157: data = 32'shFFFF55E1; //   -43551 -> sin(221.64705882352942°)
            8'd158: data = 32'shFFFF5137; //   -44745 -> sin(223.05882352941177°)
            8'd159: data = 32'shFFFF4CA9; //   -45911 -> sin(224.47058823529414°)
            8'd160: data = 32'shFFFF4837; //   -47049 -> sin(225.8823529411765°)
            8'd161: data = 32'shFFFF43E1; //   -48159 -> sin(227.29411764705884°)
            8'd162: data = 32'shFFFF3FA9; //   -49239 -> sin(228.7058823529412°)
            8'd163: data = 32'shFFFF3B8E; //   -50290 -> sin(230.11764705882354°)
            8'd164: data = 32'shFFFF3792; //   -51310 -> sin(231.52941176470588°)
            8'd165: data = 32'shFFFF33B5; //   -52299 -> sin(232.94117647058826°)
            8'd166: data = 32'shFFFF2FF8; //   -53256 -> sin(234.3529411764706°)
            8'd167: data = 32'shFFFF2C5B; //   -54181 -> sin(235.76470588235296°)
            8'd168: data = 32'shFFFF28DF; //   -55073 -> sin(237.1764705882353°)
            8'd169: data = 32'shFFFF2585; //   -55931 -> sin(238.58823529411765°)
            8'd170: data = 32'shFFFF224C; //   -56756 -> sin(240.00000000000003°)
            8'd171: data = 32'shFFFF1F36; //   -57546 -> sin(241.41176470588238°)
            8'd172: data = 32'shFFFF1C43; //   -58301 -> sin(242.82352941176472°)
            8'd173: data = 32'shFFFF1973; //   -59021 -> sin(244.23529411764707°)
            8'd174: data = 32'shFFFF16C7; //   -59705 -> sin(245.64705882352942°)
            8'd175: data = 32'shFFFF1440; //   -60352 -> sin(247.05882352941177°)
            8'd176: data = 32'shFFFF11DC; //   -60964 -> sin(248.47058823529414°)
            8'd177: data = 32'shFFFF0F9E; //   -61538 -> sin(249.8823529411765°)
            8'd178: data = 32'shFFFF0D86; //   -62074 -> sin(251.29411764705884°)
            8'd179: data = 32'shFFFF0B93; //   -62573 -> sin(252.7058823529412°)
            8'd180: data = 32'shFFFF09C6; //   -63034 -> sin(254.11764705882354°)
            8'd181: data = 32'shFFFF081F; //   -63457 -> sin(255.5294117647059°)
            8'd182: data = 32'shFFFF069F; //   -63841 -> sin(256.94117647058823°)
            8'd183: data = 32'shFFFF0545; //   -64187 -> sin(258.3529411764706°)
            8'd184: data = 32'shFFFF0413; //   -64493 -> sin(259.764705882353°)
            8'd185: data = 32'shFFFF0308; //   -64760 -> sin(261.1764705882353°)
            8'd186: data = 32'shFFFF0224; //   -64988 -> sin(262.5882352941177°)
            8'd187: data = 32'shFFFF0167; //   -65177 -> sin(264.0°)
            8'd188: data = 32'shFFFF00D2; //   -65326 -> sin(265.4117647058824°)
            8'd189: data = 32'shFFFF0065; //   -65435 -> sin(266.8235294117647°)
            8'd190: data = 32'shFFFF001F; //   -65505 -> sin(268.2352941176471°)
            8'd191: data = 32'shFFFF0001; //   -65535 -> sin(269.64705882352945°)
            8'd192: data = 32'shFFFF000B; //   -65525 -> sin(271.05882352941177°)
            8'd193: data = 32'shFFFF003D; //   -65475 -> sin(272.47058823529414°)
            8'd194: data = 32'shFFFF0096; //   -65386 -> sin(273.88235294117646°)
            8'd195: data = 32'shFFFF0118; //   -65256 -> sin(275.29411764705884°)
            8'd196: data = 32'shFFFF01C0; //   -65088 -> sin(276.7058823529412°)
            8'd197: data = 32'shFFFF0291; //   -64879 -> sin(278.11764705882354°)
            8'd198: data = 32'shFFFF0388; //   -64632 -> sin(279.5294117647059°)
            8'd199: data = 32'shFFFF04A7; //   -64345 -> sin(280.94117647058823°)
            8'd200: data = 32'shFFFF05ED; //   -64019 -> sin(282.3529411764706°)
            8'd201: data = 32'shFFFF075A; //   -63654 -> sin(283.764705882353°)
            8'd202: data = 32'shFFFF08EE; //   -63250 -> sin(285.1764705882353°)
            8'd203: data = 32'shFFFF0AA8; //   -62808 -> sin(286.5882352941177°)
            8'd204: data = 32'shFFFF0C88; //   -62328 -> sin(288.0°)
            8'd205: data = 32'shFFFF0E8D; //   -61811 -> sin(289.4117647058824°)
            8'd206: data = 32'shFFFF10B9; //   -61255 -> sin(290.82352941176475°)
            8'd207: data = 32'shFFFF1309; //   -60663 -> sin(292.2352941176471°)
            8'd208: data = 32'shFFFF157F; //   -60033 -> sin(293.64705882352945°)
            8'd209: data = 32'shFFFF1819; //   -59367 -> sin(295.05882352941177°)
            8'd210: data = 32'shFFFF1AD7; //   -58665 -> sin(296.47058823529414°)
            8'd211: data = 32'shFFFF1DB8; //   -57928 -> sin(297.88235294117646°)
            8'd212: data = 32'shFFFF20BD; //   -57155 -> sin(299.29411764705884°)
            8'd213: data = 32'shFFFF23E4; //   -56348 -> sin(300.7058823529412°)
            8'd214: data = 32'shFFFF272E; //   -55506 -> sin(302.11764705882354°)
            8'd215: data = 32'shFFFF2A99; //   -54631 -> sin(303.5294117647059°)
            8'd216: data = 32'shFFFF2E25; //   -53723 -> sin(304.94117647058823°)
            8'd217: data = 32'shFFFF31D3; //   -52781 -> sin(306.3529411764706°)
            8'd218: data = 32'shFFFF35A0; //   -51808 -> sin(307.764705882353°)
            8'd219: data = 32'shFFFF398C; //   -50804 -> sin(309.1764705882353°)
            8'd220: data = 32'shFFFF3D98; //   -49768 -> sin(310.5882352941177°)
            8'd221: data = 32'shFFFF41C1; //   -48703 -> sin(312.0°)
            8'd222: data = 32'shFFFF4608; //   -47608 -> sin(313.4117647058824°)
            8'd223: data = 32'shFFFF4A6D; //   -46483 -> sin(314.82352941176475°)
            8'd224: data = 32'shFFFF4EED; //   -45331 -> sin(316.2352941176471°)
            8'd225: data = 32'shFFFF5389; //   -44151 -> sin(317.64705882352945°)
            8'd226: data = 32'shFFFF583F; //   -42945 -> sin(319.05882352941177°)
            8'd227: data = 32'shFFFF5D10; //   -41712 -> sin(320.47058823529414°)
            8'd228: data = 32'shFFFF61FA; //   -40454 -> sin(321.88235294117646°)
            8'd229: data = 32'shFFFF66FD; //   -39171 -> sin(323.29411764705884°)
            8'd230: data = 32'shFFFF6C17; //   -37865 -> sin(324.7058823529412°)
            8'd231: data = 32'shFFFF7148; //   -36536 -> sin(326.11764705882354°)
            8'd232: data = 32'shFFFF7690; //   -35184 -> sin(327.5294117647059°)
            8'd233: data = 32'shFFFF7BED; //   -33811 -> sin(328.94117647058823°)
            8'd234: data = 32'shFFFF815E; //   -32418 -> sin(330.3529411764706°)
            8'd235: data = 32'shFFFF86E3; //   -31005 -> sin(331.764705882353°)
            8'd236: data = 32'shFFFF8C7B; //   -29573 -> sin(333.1764705882353°)
            8'd237: data = 32'shFFFF9225; //   -28123 -> sin(334.5882352941177°)
            8'd238: data = 32'shFFFF97E0; //   -26656 -> sin(336.0°)
            8'd239: data = 32'shFFFF9DAB; //   -25173 -> sin(337.4117647058824°)
            8'd240: data = 32'shFFFFA386; //   -23674 -> sin(338.82352941176475°)
            8'd241: data = 32'shFFFFA96E; //   -22162 -> sin(340.2352941176471°)
            8'd242: data = 32'shFFFFAF65; //   -20635 -> sin(341.64705882352945°)
            8'd243: data = 32'shFFFFB567; //   -19097 -> sin(343.05882352941177°)
            8'd244: data = 32'shFFFFBB76; //   -17546 -> sin(344.47058823529414°)
            8'd245: data = 32'shFFFFC18F; //   -15985 -> sin(345.8823529411765°)
            8'd246: data = 32'shFFFFC7B2; //   -14414 -> sin(347.29411764705884°)
            8'd247: data = 32'shFFFFCDDD; //   -12835 -> sin(348.7058823529412°)
            8'd248: data = 32'shFFFFD410; //   -11248 -> sin(350.11764705882354°)
            8'd249: data = 32'shFFFFDA4A; //    -9654 -> sin(351.5294117647059°)
            8'd250: data = 32'shFFFFE08A; //    -8054 -> sin(352.94117647058823°)
            8'd251: data = 32'shFFFFE6CF; //    -6449 -> sin(354.3529411764706°)
            8'd252: data = 32'shFFFFED18; //    -4840 -> sin(355.764705882353°)
            8'd253: data = 32'shFFFFF364; //    -3228 -> sin(357.1764705882353°)
            8'd254: data = 32'shFFFFF9B1; //    -1615 -> sin(358.5882352941177°)
            8'd255: data = 32'sh00000000; //        0 -> sin(360.0°)
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
