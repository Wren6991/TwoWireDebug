// ----------------------------------------------------------------------------
// Part of the Two-Wire Debug project, original (c) Luke Wren 2022
// SPDX-License-Identifier CC0-1.0
// ----------------------------------------------------------------------------

// Debug Transport Module

// Bridges a Two-Wire Debug serial bus to a downstream address-mapped bus.

`default_nettype none

module twowire_dtm #(
	// Address size = 8 * (1 + ASIZE) bits. Maximum 64 bits.
	parameter ASIZE = 0
) (
	// Debug clock and debug reset
	input  wire                     dck,
	input  wire                     drst_n,

	// DIO pad connections (active-*high* output enable)
	output wire                     do,
	output wire                     doe,
	input  wire                     di,

	// Status signals
	output wire                     host_connected,

	// System reset request/acknowledge


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

// ----------------------------------------------------------------------------
// IO registers

// No logic between IO registers and the pad.
wire do_next;
wire doe_next;
wire di_q;

twowire_dtm_io_flops io_flops_u (
	.dck    (dck),
	.drst_n (drst_n),

	.do     (do_next),
	.do_q   (do),

	.doe    (doe_next),
	.doe_q  (doe),

	.di     (di),
	.di_q   (di_q)
);

// ----------------------------------------------------------------------------
// Connect sequence monitor

wire [3:0] mdropaddr = 4'h00; // TODO driven from CSR

reg connected_prev;
wire connect_now;
wire connected = connected_prev || connect_now;

assign host_connected = connected;

always @ (posedge dck or negedge drst_n) begin
	if (!drst_n) begin
		connected_prev <= 1'b0;
	end else begin
		connected_prev <= connected;
	end
end

twowire_dtm_connect_monitor connect_monitor_u (
	.dck         (dck),
	.drst_n      (drst_n),
	.di_q        (di_q),
	.mdropaddr   (mdropaddr),
	.connect_now (connect_now),
	.connected   (connected)
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif