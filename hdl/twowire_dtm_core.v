// ----------------------------------------------------------------------------
// Part of the Two-Wire Debug project, original (c) Luke Wren 2022
// SPDX-License-Identifier CC0-1.0
// ----------------------------------------------------------------------------

// DTM core implementation: registers, and downstream bus interface logic.

`default_nettype none

module twowire_dtm_core #(
	parameter W_CMD = 4,
	parameter ASIZE = 0,
	parameter IDCODE = 32'h00000000
) (
	input  wire                     dck,
	input  wire                     drst_n,

	input  wire                     connected,
	output reg                      disconnect_now,

	input  wire [W_CMD-1:0]         cmd,
	input  wire                     cmd_vld,
	output reg                      cmd_payload_end,

	input  wire                     serial_parity_err,

	input  wire                     serial_wdata,
	input  wire                     serial_wdata_vld,
	output wire                     serial_rdata,
	input  wire                     serial_rdata_rdy,

	// Downstream bus (APB3 ish)
	output wire [8*(1 + ASIZE)-1:0] dst_paddr,
	output wire                     dst_psel,
	output wire                     dst_penable,
	output wire                     dst_pwrite,
	input  wire                     dst_pready,
	input  wire                     dst_pslverr,
	output wire [31:0]              dst_pwdata,
	input  wire [31:0]              dst_prdata
);

localparam W_ADDR = 8 * (1 + ASIZE);
localparam W_SREG = W_ADDR > 32 ? W_ADDR : 32;

function [63:0] byteswap_64; input [63:0] i; begin
	byteswap_64 = {i[7:0], i[15:8], i[23:16], i[31:24], i[39:32], i[47:40], i[55:48], i[63:56]};
end endfunction

function [W_SREG-1:0] byteswap_sreg; input [W_SREG-1:0] i; begin
	byteswap_sreg = byteswap_64({32'h0, i} << (64 - W_SREG));
end endfunction

// ----------------------------------------------------------------------------

localparam CMD_DISCONNECT = 4'h0;
localparam CMD_R_IDCODE   = 4'h1;
localparam CMD_R_CSR      = 4'h2;
localparam CMD_W_CSR      = 4'h3;
localparam CMD_R_ADDR     = 4'h4;
localparam CMD_W_ADDR     = 4'h5;
localparam CMD_R_DATA     = 4'h7;
localparam CMD_R_BUFF     = 4'h8;
localparam CMD_W_DATA     = 4'h9;

wire cmd_is_write =
	cmd == CMD_W_CSR ||
	cmd == CMD_W_ADDR ||
	cmd == CMD_W_DATA;

// ----------------------------------------------------------------------------

localparam W_STATE = 1;
localparam S_IDLE  = 1'd0;
localparam S_SHIFT = 1'd1;

reg [W_STATE-1:0] state;
reg [W_STATE-1:0] state_nxt;
reg [5:0]         bit_ctr;
reg [5:0]         bit_ctr_nxt;
reg [W_SREG-1:0]  sreg;
reg [W_SREG-1:0]  sreg_nxt;

wire shift_en = cmd_is_write ? serial_wdata_vld : serial_rdata_rdy;

always @ (*) begin
	state_nxt = state;
	bit_ctr_nxt = bit_ctr;

	disconnect_now = 1'b0;
	cmd_payload_end = 1'b0;

	case (state)
	S_IDLE: if (cmd_vld) begin
		case (cmd)
		CMD_DISCONNECT: begin
			disconnect_now = 1'b1;
		end
		CMD_R_IDCODE: begin
			bit_ctr_nxt = 6'h1f;
			sreg_nxt = byteswap_sreg(IDCODE);
			state_nxt = S_SHIFT;
		end
		endcase
	end
	S_SHIFT: if (shift_en) begin
		bit_ctr_nxt = bit_ctr - 1'b1;
		if (bit_ctr == 6'h0) begin
			state_nxt = S_IDLE;
			cmd_payload_end = 1'b1;
		end
		sreg_nxt = {sreg[W_SREG-2:0], 1'b0};
		if (cmd_is_write) begin
			if (cmd == CMD_W_ADDR) begin
				sreg_nxt[W_SREG - (W_ADDR - 1)] = serial_wdata;
			end else begin
				sreg_nxt[W_SREG - 31] = serial_wdata;
			end
		end
	end
	endcase
end

always @ (posedge dck or negedge drst_n) begin
	if (!drst_n) begin
		state <= S_IDLE;
		bit_ctr <= 6'h0;
		sreg <= {W_SREG{1'b0}};
	end else begin
		state <= state_nxt;
		bit_ctr <= bit_ctr_nxt;
		sreg <= sreg_nxt;
	end
end

assign serial_rdata = sreg[W_SREG - 1];

endmodule

`ifndef YOSYS
`default_nettype wire
`endif