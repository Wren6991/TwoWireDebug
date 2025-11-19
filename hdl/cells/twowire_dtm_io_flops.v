// ----------------------------------------------------------------------------
// Part of the Two-Wire Debug project, original (c) Luke Wren 2022
// SPDX-License-Identifier CC0-1.0
// ----------------------------------------------------------------------------

// IO registers for the DIO pin.

// This file can be reimplemented with appropriate register instances for your
// platform (e.g FPGA IO register macros), or replaced with wires so that a
// registered IO cell can be instantiated externally.

`default_nettype none

`ifndef TWOWIRE_REG_KEEP_ATTR
`define TWOWIRE_REG_KEEP_ATTR (*keep=1'b1*)
`endif

module twowire_dtm_io_flops (
	input  wire dck,
	input  wire drst_n,

	input  wire dout,
	output wire dout_q,

	input  wire doe,
	output wire doe_q,

	input  wire di,
	output wire di_q
);

`TWOWIRE_REG_KEEP_ATTR reg dout_reg;
`TWOWIRE_REG_KEEP_ATTR reg doe_reg;
`TWOWIRE_REG_KEEP_ATTR reg di_reg;

always @ (posedge dck or negedge drst_n) begin
	if (!drst_n) begin
		dout_reg  <= 1'b0;
		doe_reg <= 1'b0;
		di_reg  <= 1'b0;
	end else begin
		dout_reg  <= dout;
		doe_reg <= doe;
		di_reg  <= di;
	end
end

assign dout_q = dout_reg;
assign doe_q  = doe_reg;
assign di_q   = di_reg;

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
