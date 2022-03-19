// ----------------------------------------------------------------------------
// Part of the Two-Wire Debug project, original (c) Luke Wren 2022
// SPDX-License-Identifier CC0-1.0
// ----------------------------------------------------------------------------

// Watch DIO for a valid Connect sequence.

`default_nettype none

module twowire_dtm_connect_monitor (
	input  wire       dck,
	input  wire       drst_n,

	input  wire       di_q,
	input  wire [3:0] mdropaddr,

	output wire       connect_now,
	input  wire       connected
);

localparam LFSR_TAPS = 6'h30;
localparam LFSR_INIT = 6'h29;

reg [5:0] lfsr;
wire      lfsr_out = lfsr[5];
wire      seq_restart;

always @ (posedge dck or negedge drst_n) begin
	if (!drst_n) begin
		lfsr <= LFSR_INIT;
	end else if (seq_restart) begin
		lfsr <= LFSR_INIT;
	end else begin
		lfsr <= {lfsr[4:0], ^(lfsr & LFSR_TAPS)};
	end
end

// Connect sequence consists of:
// - Some number of zeroes from the host that doesn't appear elsewhere in the
//   sequence (sync/preamble) which basically clears this sequence counter
// - 64 bits of LFSR output, starting and ending with a `1` bit
// - 4-bit target address, followed by its bitwise complement

reg [6:0] seq_ctr;
assign seq_restart = connected ||
	!seq_ctr[6] && di_q != lfsr_out ||                              // LFSR seq mismatch
	 seq_ctr[6] && (di_q ^ seq_ctr[2]) != mdropaddr[~seq_ctr[1:0]]; // Address mismatch

always @ (posedge dck or negedge drst_n) begin
	if (!drst_n) begin
		seq_ctr <= 7'h00;
	end else if (seq_restart) begin
		seq_ctr <= 7'h00;
	end else begin
		seq_ctr <= seq_ctr + 7'h01;
	end
end

assign connect_now = seq_ctr == 7'h47 && di_q == !mdropaddr[0];

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
