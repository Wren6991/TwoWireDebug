#include "tb.h"
#include "twd_util.h"

int main() {
	tb t("waves.vcd");
	connect_target(t, 0);
	uint32_t csr;
	tb_assert(read_csr(t, &csr), "Bad parity on CSR read\n");
	printf("CSR: %08x\n", csr);
	tb_assert(csr >> 28 == 0x1u, "Bad CSR version: %u\n", csr >> 28);

	return 0;
}