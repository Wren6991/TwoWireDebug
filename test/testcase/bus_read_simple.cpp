#include "tb.h"
#include "twd_util.h"

// Check that read addresses make it to the bus interface, and read data makes
// it back. (Smoke test)

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
	uint32_t csr;
	tb_assert(read_csr(t, &csr), "Bad parity on CSR read\n");
	unsigned int asize = (csr & CSR_ASIZE_BITS) >> CSR_ASIZE_LSB;
	unsigned int addr_width = 8 * (1 + asize);
	printf("Address size: %u bits\n", addr_width);

	for (unsigned int i = 0; i < addr_width; ++i) {
		write_addr(t, 1ul << i, asize);
		uint32_t data = read_data(t);
		data = read_buf(t);
		uint32_t expect = read_data_func(1ul << i);
		tb_assert(data == expect, "Bad readback, expected %08x, got %08x\n", expect, data);
	}

	return 0;
}