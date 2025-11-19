// ----------------------------------------------------------------------------
// Part of the Two-Wire Debug project, original (c) Luke Wren 2022
// SPDX-License-Identifier CC0-1.0
// ----------------------------------------------------------------------------

// DTM core implementation: registers, and downstream bus interface logic.

`default_nettype none

module twowire_dtm_core #(
	parameter W_CMD   = 4,
	parameter ASIZE   = 0,
	parameter IDCODE  = 32'h00000000,
	parameter N_AINFO = 1,
	parameter AINFO   = {N_AINFO{32'h00000000}}
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

	// Address info present/nonpresent status
	input  wire [N_AINFO-1:0]       ainfo_present,

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
localparam CMD_R_AINFO    = 4'hb;

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

wire             bus_busy;

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
reg [31:0] ainfo_rdata;

always @ (*) begin
	state_nxt = state;
	bit_ctr_nxt = bit_ctr;
	sreg_nxt = sreg;

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
				5'h00,             // reserved
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
				csr_mdropaddr
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
			sreg_nxt = byteswap_sreg(bus_dbuf);
		end
		CMD_R_BUFF: begin
			bit_ctr_nxt = 6'h1f;
			state_nxt = S_SHIFT;
			sreg_nxt = byteswap_sreg(bus_dbuf);
		end
		CMD_W_CSR: begin
			bit_ctr_nxt = 6'h1f;
			state_nxt = S_SHIFT;
		end

		CMD_W_ADDR: begin
			bit_ctr_nxt = W_ADDR - 1;
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
		CMD_R_AINFO: begin
			bit_ctr_nxt = 6'h1f;
			state_nxt = S_SHIFT;
			sreg_nxt = ainfo_rdata;
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

wire read_data  = state == S_IDLE && cmd_vld && cmd == CMD_R_DATA;
wire read_buff  = state == S_IDLE && cmd_vld && cmd == CMD_R_BUFF;
wire read_ainfo = state == S_IDLE && cmd_vld && cmd == CMD_R_AINFO;

// ----------------------------------------------------------------------------
// CSR update

wire [31:0] csr_wdata = byteswap_sreg(sreg);

always @ (posedge dck or negedge drst_n) begin
	if (!drst_n) begin
		csr_aincr <= 1'b0;
		csr_ndtmreset <= 1'b0;
		csr_mdropaddr <= 4'h0;
	end else if (write_csr) begin
		csr_aincr <= csr_wdata[12];
		csr_ndtmreset <= csr_wdata[4];
		csr_mdropaddr <= csr_wdata[3:0];
	end
end

assign mdropaddr = csr_mdropaddr;

reg ndtmresetack_prev;

always @ (posedge dck or negedge drst_n) begin
	if (!drst_n) begin
		ndtmresetack_prev <= 1'b1;
		csr_ndtmresetack <= 1'b0;
	end else begin
		// Set by rising edge of ACK, cleared by writing to CSR.
		ndtmresetack_prev <= ndtmresetack;
		csr_ndtmresetack <= (csr_ndtmresetack && !(write_csr && csr_wdata[5])) ||
			(ndtmresetack && !ndtmresetack_prev);
	end
end

wire set_errflag_busfault;
wire set_errflag_busy;

always @ (posedge dck or negedge drst_n) begin
	if (!drst_n) begin
		errflag_parity   <= 1'b0;
		errflag_busy     <= 1'b0;
		errflag_busfault <= 1'b0;
	end else begin
		errflag_parity <= (errflag_parity
			&& !(write_csr && csr_wdata[18])) || serial_parity_err;
		errflag_busfault <= (errflag_busfault
			&& !(write_csr && csr_wdata[17])) || set_errflag_busfault;
		errflag_busy <= (errflag_busy
			&& !(write_csr && csr_wdata[16])) || set_errflag_busy;
	end
end

// ----------------------------------------------------------------------------
// Address info table

localparam W_AINFO_ADDR = N_AINFO > 1 ? $clog2(N_AINFO) : 1;

always @ (*) begin: ainfo_rport
	reg [W_AINFO_ADDR:0] i;
	ainfo_rdata = 32'h0;
	for (i = 0; i < N_AINFO; i = i + 1) begin
		if (i[W_AINFO_ADDR-1:0] == bus_addr[W_AINFO_ADDR-1:0]) begin
			ainfo_rdata = {
				AINFO[32 * i + 2 +: 30],
				ainfo_present[i],
				AINFO[32 * i]
			};
		end
	end
end

// ----------------------------------------------------------------------------
// Bus interface

reg psel;
reg penable;
reg pwrite;

always @ (posedge dck or negedge drst_n) begin
	if (!drst_n) begin
		psel <= 1'b0;
		penable <= 1'b0;
		pwrite <= 1'b0;
		bus_addr <= {W_ADDR{1'b0}};
		bus_dbuf <= {W_DATA{1'b0}};
	end else if (psel) begin
		if (!penable) begin
			penable <= 1'b1;
		end else if (dst_pready) begin
			psel <= 1'b0;
			penable <= 1'b0;
			if (!pwrite) begin
				bus_dbuf <= dst_prdata;
			end
			if (csr_aincr && !dst_pslverr) begin
				bus_addr <= bus_addr + 1'b1;
			end
		end
	end else if (!errflag_any) begin
		if (write_addr) begin
			bus_addr <= byteswap_sreg(sreg);
		end else if (write_data) begin
			psel <= 1'b1;
			pwrite <= 1'b1;
			bus_dbuf <= byteswap_sreg(sreg);
		end else if (read_data) begin
			psel <= 1'b1;
			pwrite <= 1'b0;
		end else if (read_ainfo && csr_aincr) begin
			bus_addr <= bus_addr + 1'b1;
		end
	end
end

assign bus_busy = psel;

assign dst_psel = psel;
assign dst_penable = penable;
assign dst_pwrite = pwrite;
assign dst_paddr = bus_addr;
assign dst_pwdata = bus_dbuf;

assign set_errflag_busfault = dst_penable && dst_pready && dst_pslverr;

assign set_errflag_busy = dst_psel && (
	write_addr ||
	write_data ||
	read_data ||
	read_buff ||
	(read_ainfo && csr_aincr)
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
