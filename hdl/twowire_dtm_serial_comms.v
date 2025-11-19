// ----------------------------------------------------------------------------
// Part of the Two-Wire Debug project, original (c) Luke Wren 2022
// SPDX-License-Identifier CC0-1.0
// ----------------------------------------------------------------------------

// DTM serial communications unit

// - Detect command/data framing
// - Drive DO/DOE pad outputs
// - Generate and check parity bits

`default_nettype none

module twowire_dtm_serial_comms #(
	parameter W_CMD = 4
) (
	input  wire             dck,
	input  wire             drst_n,

	input  wire             di_q,
	output reg              dout_nxt,
	output reg              doe_nxt,

	input  wire             connected,

	output wire [W_CMD-1:0] cmd,
	output reg              cmd_vld,
	input  wire             cmd_payload_end,

	output reg              parity_err,

	output wire             wdata,
	output reg              wdata_vld,
	input  wire             rdata,
	output reg              rdata_rdy
);

localparam W_STATE      = 4;
localparam S_IDLE       = 4'd0;
localparam S_CMD0       = 4'd1;
localparam S_CMD1       = 4'd2;
localparam S_CMD2       = 4'd3;
localparam S_CMD3       = 4'd4;
localparam S_CMD_PARITY = 4'd5;
localparam S_CTURN0     = 4'd6;
localparam S_CTURN1     = 4'd7;
localparam S_DATA       = 4'd8;
localparam S_PARITY0    = 4'd9;
localparam S_PARITY1    = 4'd10;
localparam S_PARITY2    = 4'd11;
localparam S_PARITY3    = 4'd12;

reg [W_STATE-1:0] state;
reg [W_STATE-1:0] state_nxt;
reg [W_CMD-1:0]   cmd_sreg;
reg [W_CMD-1:0]   cmd_sreg_nxt;
reg               parity;
reg               parity_nxt;

// Odd parity.
wire cmd_parity_expect = ~^cmd_sreg;
// All read commands have a parity bit of 0, to park DIO before turnaround.
wire cmd_is_write = cmd_parity_expect;

assign wdata = di_q;

// As a general note: the fact that our DIO input and output paths are both
// registered (for timing hygiene on DI, and to avoid glitches on DO) means
// that at any given point in time, we are seeing DIO as it was one cycle
// ago, and generating the value it will take in one cycle's time. This makes
// the read side of this state machine a more confusing than the write side,
// since it's always planning two cycles in advance.

always @ (*) begin
	state_nxt = state;
	cmd_sreg_nxt = cmd_sreg;
	parity_nxt = 1'b1;

	doe_nxt = 1'b0;
	dout_nxt = 1'b0;

	cmd_vld = 1'b0;
	parity_err = 1'b0;
	wdata_vld = 1'b0;
	rdata_rdy = 1'b0;

	case (state)
	S_IDLE: begin
		if (di_q) begin
			// Start bit detected
			state_nxt = S_CMD0;
		end
	end
	S_CMD0: begin
		cmd_sreg_nxt = {cmd_sreg[W_CMD-2:0], di_q};
		state_nxt = S_CMD1;
	end
	S_CMD1: begin
		cmd_sreg_nxt = {cmd_sreg[W_CMD-2:0], di_q};
		state_nxt = S_CMD2;
	end
	S_CMD2: begin
		cmd_sreg_nxt = {cmd_sreg[W_CMD-2:0], di_q};
		state_nxt = S_CMD3;
	end
	S_CMD3: begin
		cmd_sreg_nxt = {cmd_sreg[W_CMD-2:0], di_q};
		state_nxt = S_CMD_PARITY;
	end
	S_CMD_PARITY: begin
		if (di_q == cmd_parity_expect) begin
			cmd_vld = 1'b1;
			// Read skips CTURNx state: during the first turnaround cycle
			// (from our PoV; the first observed on di_q) we are actually
			// reading the first data bit from the DTM core and presenting it
			// to the DO/DOE registers
			state_nxt = cmd_is_write ? S_CTURN0 : S_DATA;
		end else begin
			parity_err = 1'b1;
			state_nxt = S_IDLE;
		end
	end
	S_CTURN0: begin
		state_nxt = S_CTURN1;
	end
	S_CTURN1: begin
		state_nxt = S_DATA;
	end
	S_DATA: begin
		if (cmd_is_write) begin
			wdata_vld = 1'b1;
			parity_nxt = parity ^ wdata;
		end else begin
			rdata_rdy = 1'b1;
			doe_nxt = 1'b1;
			dout_nxt = rdata;
			parity_nxt = parity ^ rdata;
		end
		if (cmd_payload_end) begin
			state_nxt = S_PARITY0;
		end
	end
	S_PARITY0: begin
		if (cmd_is_write) begin
			if (di_q == parity) begin
				state_nxt = S_PARITY1;
			end else begin
				parity_err = 1'b1;
				state_nxt = S_IDLE;
			end
		end else begin
			doe_nxt = 1'b1;
			dout_nxt = parity;
			state_nxt = S_PARITY1;
		end
	end
	S_PARITY1: begin
		if (!cmd_is_write) begin
			// Park DIO for turnaround
			doe_nxt = 1'b1;
			dout_nxt = 1'b0;
		end
		state_nxt = S_PARITY2;
	end
	S_PARITY2: begin
		state_nxt = S_PARITY3;
	end
	S_PARITY3: begin
		state_nxt = S_IDLE;
	end
	endcase

	if (!connected) begin
		// Override previous assignments. Force serial unit back to idle state.
		state_nxt = S_IDLE;
		doe_nxt = 1'b0;
		dout_nxt = 1'b0;
	end
end

always @ (posedge dck or negedge drst_n) begin
	if (!drst_n) begin
		state <= S_IDLE;
		cmd_sreg <= {W_CMD{1'b0}};
		parity <= 1'b0;
	end else begin
		state <= state_nxt;
		cmd_sreg <= cmd_sreg_nxt;
		parity <= parity_nxt;
	end
end

assign cmd = cmd_sreg;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
