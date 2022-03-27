// ----------------------------------------------------------------------------
// Part of the Two-Wire Debug project, original (c) Luke Wren 2022
// SPDX-License-Identifier CC0-1.0
// ----------------------------------------------------------------------------

// Debug Transport Module

// Bridges a Two-Wire Debug serial bus to a downstream address-mapped bus.

`default_nettype none

module twowire_dtm #(
	// If IDCODE[0] == 1'b1, this is formatted as a JTAG IDCODE register.
	// If all-zeroes, no identifier provided.
	parameter IDCODE    = 32'h0,

	// Address size = 8 * (1 + ASIZE) bits. Maximum 64 bits.
	parameter ASIZE     = 0,

	// AINFO entry count and entries (including the VALID=0 entry at the end)
	parameter N_AINFO   = 1,
	// Listed highest-numbered entry first
	parameter AINFO     = {N_AINFO{32'h0}},

	// Do not modify
	parameter W_ADDR    = 8 * (1 + ASIZE), // do not modify
	parameter W_DATA    = 32               // do not modify
) (
	// Debug clock and debug reset
	input  wire                     dck,
	input  wire                     drst_n,

	// DIO pad connections
	output wire                     do,
	output wire                     doe,
	input  wire                     di,

	// Status signals
	output wire                     host_connected,

	// Tie to 1'b0 if no AINFO is present
	input  wire [N_AINFO-1:0]       ainfo_present,

	// Downstream bus (APB3 ish)
	output wire [W_ADDR-1:0]        dst_paddr,
	output wire                     dst_psel,
	output wire                     dst_penable,
	output wire                     dst_pwrite,
	input  wire                     dst_pready,
	input  wire                     dst_pslverr,
	output wire [W_DATA-1:0]        dst_pwdata,
	input  wire [W_DATA-1:0]        dst_prdata
);

// ----------------------------------------------------------------------------
// IO registers

// No logic between IO registers and the pad.
wire do_nxt;
wire doe_nxt;
wire di_q;

twowire_dtm_io_flops io_flops_u (
	.dck    (dck),
	.drst_n (drst_n),

	.do     (do_nxt),
	.do_q   (do),

	.doe    (doe_nxt),
	.doe_q  (doe),

	.di     (di),
	.di_q   (di_q)
);

// ----------------------------------------------------------------------------
// Connect sequence monitor

wire [3:0] mdropaddr;

wire connect_now;

twowire_dtm_connect_monitor connect_monitor_u (
	.dck         (dck),
	.drst_n      (drst_n),
	.di_q        (di_q),
	.mdropaddr   (mdropaddr),
	.connect_now (connect_now),
	.connected   (connected)
);

reg connected;
assign host_connected = connected;

wire disconnect_now;
wire sercom_parity_err;

always @ (posedge dck or negedge drst_n) begin
	if (!drst_n) begin
		connected <= 1'b0;
	end else begin
		connected <= (connected || connect_now) && !disconnect_now && !sercom_parity_err;
	end
end

// ----------------------------------------------------------------------------
// Serial interface

localparam W_CMD = 4;

wire [W_CMD-1:0] sercom_cmd;
wire             sercom_cmd_vld;
wire             sercom_cmd_payload_end;

wire             sercom_wdata;
wire             sercom_wdata_vld;
wire             sercom_rdata;
wire             sercom_rdata_rdy;


twowire_dtm_serial_comms #(
	.W_CMD (W_CMD)
) sercom_u (
	.dck             (dck),
	.drst_n          (drst_n),

	.di_q            (di_q),
	.do_nxt          (do_nxt),
	.doe_nxt         (doe_nxt),

	.connected       (connected),

	.cmd             (sercom_cmd),
	.cmd_vld         (sercom_cmd_vld),
	.cmd_payload_end (sercom_cmd_payload_end),

	.parity_err      (sercom_parity_err),

	.wdata           (sercom_wdata),
	.wdata_vld       (sercom_wdata_vld),
	.rdata           (sercom_rdata),
	.rdata_rdy       (sercom_rdata_rdy)
);

// ----------------------------------------------------------------------------
// TDM core implementation

twowire_dtm_core #(
	.W_CMD  (W_CMD),
	.ASIZE  (ASIZE),
	.IDCODE (IDCODE)
) core_u (
	.dck               (dck),
	.drst_n            (drst_n),

	.connected         (connected),
	.disconnect_now    (disconnect_now),
	.mdropaddr         (mdropaddr),

	.cmd               (sercom_cmd),
	.cmd_vld           (sercom_cmd_vld),
	.cmd_payload_end   (sercom_cmd_payload_end),

	.serial_parity_err (sercom_parity_err),
	.serial_wdata      (sercom_wdata),
	.serial_wdata_vld  (sercom_wdata_vld),
	.serial_rdata      (sercom_rdata),
	.serial_rdata_rdy  (sercom_rdata_rdy),

	.dst_paddr         (dst_paddr),
	.dst_psel          (dst_psel),
	.dst_penable       (dst_penable),
	.dst_pwrite        (dst_pwrite),
	.dst_pready        (dst_pready),
	.dst_pslverr       (dst_pslverr),
	.dst_pwdata        (dst_pwdata),
	.dst_prdata        (dst_prdata)
);

endmodule

`ifndef YOSYS
`default_nettype wire
`endif
