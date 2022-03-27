#include "tb.h"
#include "twd_util.h"

// Check that AINCR causes addresses to increment on write

uint32_t write_data_func(uint64_t addr) {
	return (addr & 0xffffffffu) | (addr * 3 >> 32 & 0xffffffffu);
}

uint64_t bus_write_addr;
uint32_t bus_write_data;

bus_write_response write_callback(uint64_t addr, uint32_t data) {
	bus_write_addr = addr;
	bus_write_data = data;
	return {
		.delay_cycles = 0,
		.err = false
	};
}

int main() {
	tb t("waves.vcd");
	t.set_bus_write_callback(write_callback);

	connect_target(t, 0);
	uint32_t csr;
	tb_assert(read_csr(t, &csr), "Bad parity on CSR read\n");
	unsigned int asize = (csr & CSR_ASIZE_BITS) >> CSR_ASIZE_LSB;
	unsigned int addr_width = 8 * (1 + asize);
	printf("Address size: %u bits\n", addr_width);

	write_csr(t, CSR_AINCR_BITS);

	// Choose starting value such that we see carry through all addrss bits
	uint64_t start_addr = (1ull << (addr_width - 1)) - 10;
	const unsigned int n_access = 20;

	write_addr(t, start_addr, asize);

	for (unsigned int i = 0; i < n_access; ++i) {
		write_data(t, write_data_func(start_addr + i));
		tb_assert(bus_write_addr == start_addr + i, "Bad address: expected %016llx, got %016llx\n", start_addr + i, bus_write_addr);
		tb_assert(bus_write_data == write_data_func(start_addr + i),
			"Bad data: expected %08x, got %08x\n", write_data_func(start_addr + i), bus_write_data);
	}

	return 0;
}