#include "tb.h"
#include "twd_util.h"

// Check that AINCR is read/writable in the CSR, and causes addresses to
// increment on read

uint32_t read_data_func(uint64_t addr) {
	return (addr & 0xffffffffu) | (addr * 3 >> 32 & 0xffffffffu);
}

bus_read_response read_callback(uint64_t addr) {
	return {
		.data = read_data_func(addr),
		.delay_cycles = 0,
		.err = false
	};
}

int main() {
	tb t("waves.vcd");
	t.set_bus_read_callback(read_callback);

	connect_target(t, 0);
	write_csr(t, 0);
	uint32_t csr;
	read_csr(t, &csr);
	tb_assert(!(csr & CSR_AINCR_BITS), "Expecting AINCR to be cleared by writing 0s to CSR\n");
	write_csr(t, CSR_AINCR_BITS);
	read_csr(t, &csr);
	tb_assert(csr & CSR_AINCR_BITS, "Expecting AINCR to be set\n");

	unsigned int asize = (csr & CSR_ASIZE_BITS) >> CSR_ASIZE_LSB;
	unsigned int addr_width = 8 * (1 + asize);
	printf("Address size: %u bits\n", addr_width);

	// Choose starting value such that we see carry through all addrss bits
	uint64_t start_addr = (1ull << (addr_width - 1)) - 10;
	const unsigned int n_access = 20;

	write_addr(t, start_addr, asize);
	tb_assert(read_addr(t, asize) == start_addr, "Bad initial address readback\n");
	// Prime the pump
	(void)read_data(t);

	for (unsigned int i = 0; i < n_access; ++i) {
		uint64_t expect_addr = start_addr + i + 1;
		uint64_t addr = read_addr(t, asize);
		tb_assert(addr == expect_addr, "Bad address: expected %016llx, got %016llx\n", expect_addr, addr);
		uint32_t data = read_data(t);
		// Note ADDR points to the *next* item that will be read
		uint32_t expect_data = read_data_func(addr - 1);
		tb_assert(data == expect_data, "Bad data: expected %08x, got %08x\n", expect_data, data);
	}

	// Address should point just past the last data item
	uint64_t final_addr = start_addr + n_access + 1;
	tb_assert(read_addr(t, asize) == final_addr, "Bad final address\n");
	// Pick up the last data item
	uint32_t final_data = read_buf(t);
	tb_assert(final_data == read_data_func(final_addr - 1), "Bad final data\n");

	return 0;
}