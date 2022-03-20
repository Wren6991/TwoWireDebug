#include "tb.h"
#include "twd_util.h"

// Check that MDROPADDR field is read/writable, and we can connect to the DTM
// at each multidrop address.

int main() {
	tb t("waves.vcd");
	connect_target(t, 0);
	idle_clocks(t, 1);
	tb_assert(t.get_stat_connected(), "Did not connect at address 0\n");
	for (unsigned int addr = 1; addr <= 15; ++addr) {
		write_csr(t, addr << CSR_MDROPADDR_LSB);
		uint32_t csr;
		read_csr(t, &csr);
		tb_assert(((csr & CSR_MDROPADDR_BITS) >> CSR_MDROPADDR_LSB) == addr, "Failed to set address in CSR\n");
		send_command_byte(t, CMD_DISCONNECT);
		idle_clocks(t, 1);
		tb_assert(!t.get_stat_connected(), "Did not disconnect\n");
		connect_target(t, 0);
		idle_clocks(t, 1);
		tb_assert(!t.get_stat_connected(), "Target should ignore wrong multidrop address\n");
		connect_target(t, addr);
		idle_clocks(t, 1);
		tb_assert(t.get_stat_connected(), "Did not connect at address %u\n", addr);
	}

	return 0;
}