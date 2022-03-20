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
	output wire [3:0]               mdropaddr,

	// Serial interface
	input  wire [W_CMD-1:0]         cmd,
	input  wire                     cmd_vld,
	output reg                      cmd_payload_end,

	input  wire                     serial_parity_err,

	input  wire                     serial_wdata,
	input  wire                     serial_wdata_vld,
	output wire                     serial_rdata,
	input  wire                     serial_rdata_rdy,

	// Non-DTM reset request
	output wire                     ndtmresetreq,
	input  wire                     ndtmresetack,

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

localparam TWD_VERSION = 4'h1;

localparam W_ADDR = 8 * (1 + ASIZE);
localparam W_SREG = W_ADDR > 32 ? W_ADDR : 32;
localparam W_DATA = 32;

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
// Architectural state

reg [W_DATA-1:0] bus_dbuf;
reg [W_ADDR-1:0] bus_addr;

reg              errflag_parity;
reg              errflag_busfault;
reg              errflag_busy;
wire             errflag_any = errflag_parity || errflag_busfault || errflag_busy;

reg              bus_busy;

reg              csr_aincr;
reg              csr_ndtmreset;
reg              csr_ndtmresetack;
reg [3:0]        csr_mdropaddr;

// ----------------------------------------------------------------------------
// Shift register, and register read/write interface

localparam W_STATE = 2;
localparam S_IDLE  = 2'd0;
localparam S_SHIFT = 2'd1;
localparam S_WRITE = 2'd2;

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
			state_nxt = S_SHIFT;
			sreg_nxt = byteswap_sreg(IDCODE);
		end
		CMD_R_CSR: begin
			bit_ctr_nxt = 6'h1f;
			state_nxt = S_SHIFT;
			sreg_nxt = byteswap_sreg({
				TWD_VERSION,
				1'b0,             // reserved
				ASIZE[2:0],
				1'b0,             // reserved
				errflag_parity,
				errflag_busfault,
				errflag_busy,
				3'h0,
				csr_aincr,
				3'h0,             // reserved
				bus_busy,
				2'h0,             // reserved
				csr_ndtmresetack,
				csr_ndtmreset,
				csr_mdropaddr,
				4'h0              // reserved
			});
		end
		CMD_R_ADDR: begin
			bit_ctr_nxt = W_ADDR - 1;
			state_nxt = S_SHIFT;
			sreg_nxt = byteswap_sreg(bus_addr);
		end
		CMD_R_DATA: begin
			bit_ctr_nxt = 6'h1f;
			state_nxt = S_SHIFT;
			sreg_nxt = bus_dbuf;
		end
		CMD_R_BUFF: begin
			bit_ctr_nxt = 6'h1f;
			state_nxt = S_SHIFT;
			sreg_nxt = bus_dbuf;
		end
		CMD_W_CSR: begin
			bit_ctr_nxt = 6'h1f;
			state_nxt = S_SHIFT;
		end

		CMD_W_ADDR: begin
			bit_ctr_nxt = W_ADDR;
			state_nxt = S_SHIFT;
		end
		CMD_W_CSR: begin
			bit_ctr_nxt = 6'h1f;
			state_nxt = S_SHIFT;
		end
		CMD_W_DATA: begin
			bit_ctr_nxt = 6'h1f;
			state_nxt = S_SHIFT;
		end
		default: begin
			disconnect_now = 1'b1;
		end
		endcase
	end
	S_SHIFT: if (shift_en) begin
		bit_ctr_nxt = bit_ctr - 1'b1;
		if (bit_ctr == 6'h0) begin
			state_nxt = cmd_is_write ? S_WRITE : S_IDLE;
			cmd_payload_end = 1'b1;
		end
		sreg_nxt = {sreg[W_SREG-2:0], 1'b0};
		if (cmd_is_write) begin
			if (cmd == CMD_W_ADDR) begin
				sreg_nxt[W_SREG - W_ADDR] = serial_wdata;
			end else begin
				sreg_nxt[W_SREG - 32] = serial_wdata;
			end
		end
	end
	S_WRITE: begin
		state_nxt = S_IDLE;
		// Update logic is outside of this state machine.
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

wire write_csr  = state == S_WRITE && cmd == CMD_W_CSR;
wire write_addr = state == S_WRITE && cmd == CMD_W_ADDR;
wire write_data = state == S_WRITE && cmd == CMD_W_DATA;

// ----------------------------------------------------------------------------
// CSR update

wire [31:0] csr_wdata = byteswap_sreg(sreg);

always @ (posedge dck or negedge drst_n) begin
	if (!drst_n) begin
		csr_mdropaddr <= 4'h0;
	end else if (write_csr) begin
		csr_mdropaddr <= csr_wdata[7:4];
	end
end

assign mdropaddr = csr_mdropaddr;

// ----------------------------------------------------------------------------
// Bus interface


endmodule

`ifndef YOSYS
`default_nettype wire
`endif