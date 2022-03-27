#include "tb.h"
#include "twd_util.h"

// Send a command with bad parity, and check that the target
// - Disconnects from the bus
// - Sets EPARITY in the CSR
// - Allows EPARITY to be cleared by writing 1

int main() {
	tb t("waves.vcd");
	connect_target(t, 0);
	idle_clocks(t, 8);
	tb_assert(t.get_stat_connected(), "Did not connect\n");

	uint8_t bad_cmd_byte =
		1u << 7 |
		CMD_R_IDCODE << 3 |
		1u << 2; // Parity fail
	put_bits(t, &bad_cmd_byte, 8);
	tb_assert(!t.get_stat_connected(), "Did not disconnect\n");

	connect_target(t, 0);
	idle_clocks(t, 8);
	tb_assert(t.get_stat_connected(), "Did not reconnect\n");

	uint32_t csr;
	tb_assert(read_csr(t, &csr), "Bad parity on CSR read post reconnect\n");
	tb_assert(csr & CSR_EPARITY_BITS, "CSR.EPARITY should be set\n");
	tb_assert(!(csr & (CSR_EBUSFAULT_BITS | CSR_EBUSY_BITS)), "Other error flags should not be set\n");

	write_csr(t, CSR_EPARITY_BITS);
	tb_assert(read_csr(t, &csr), "Bad parity on CSR read after clearing EPARITY\n");
	tb_assert(!(csr & CSR_EPARITY_BITS), "CSR.EPARITY should be cleared\n");
	tb_assert(t.get_stat_connected(), "Disconnected after clearing EPARITY?\n");
 
	return 0;
}