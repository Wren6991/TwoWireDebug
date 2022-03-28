#include "tb.h"
#include "twd_util.h"

// Check that AINCR causes ADDR to increment when a write transfer completes

uint32_t write_data_func(uint64_t addr) {
	return (addr & 0xffffffffu) | (addr * 3 >> 32 & 0xffffffffu);
}

std::vector<std::pair<uint64_t, uint32_t>> write_history;

bus_write_response write_callback(uint64_t addr, uint32_t data) {
	write_history.push_back(std::pair<uint64_t, uint32_t>(addr, data));
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

	for (unsigned int i = 0; i < addr_width; ++i) {
		write_addr(t, 1ul << i, asize);
		write_data(t, write_data_func(1ul << i));
	}

	tb_assert(read_csr(t, &csr), "Bad parity on CSR read\n");


	for (unsigned int i = 0; i < addr_width; ++i) {
		tb_assert(i < write_history.size(), "Not enough items\n");
		tb_assert(write_history[i].first == 1u << i, "Bad address at item %u\n", i);
		tb_assert(write_history[i].second == write_data_func(1u << i), "Bad data at item %u\n", i);
	}

	return 0;
}