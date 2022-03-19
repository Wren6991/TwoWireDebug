#include "tb.h"
#include "twd_util.h"

int main() {
	tb t("waves.vcd");
	connect_target(t, 0);

	uint8_t idcode8[4];
	send_command_byte(t, CMD_R_IDCODE);
	get_bits(t, idcode8, 32);

	uint32_t idcode32 = bytes_to_ule32(idcode8);
	printf("IDCODE: %08x\n", idcode32);
	tb_assert(idcode32 == 0xdeadbeefu, "Bad IDCODE\n");

	tb_assert(check_parity_byte(t, idcode8, 32), "Bad parity on IDCODE read\n");
	return 0;
}