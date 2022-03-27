#include "tb.h"
#include "twd_util.h"

// Check that a connect sequence preceded by an aborted partial connect
// sequence still causes the target to connect (as per spec)

void partial_connect_sequence(tb &t, uint8_t addr, unsigned int len) {
	if (len == 0)
		return;
	if (len <= 144) {
		put_bits(t, seq_connect_noaddr, len - len % 8);
		if (len % 8 != 0) {
			uint8_t tail = seq_connect_noaddr[len / 8];
			tail >>= 8 - (len % 8);
			put_bits(t, &tail, len % 8);
		}
	}
	else {
		put_bits(t, seq_connect_noaddr, 144);
		uint8_t addr_byte = (addr & 0xfu) << 4 | (~addr & 0xfu);
		if (len % 8 == 0) {
			put_bits(t, &addr_byte, 8);
		}
		else {
			addr_byte >>= 8 - (len % 8);
			put_bits(t, &addr_byte, len % 8);
		}
	}
}


int main() {
	tb t("waves.vcd");
	for (int i = 1; i < 152; ++i) {
		partial_connect_sequence(t, 0, i);
		tb_assert(!t.get_stat_connected(), "Connected part way through sequence?!\n");
		connect_target(t, 0);
		idle_clocks(t, 1);
		tb_assert(t.get_stat_connected(), "Failed to connect with prefix length %d\n", i);
		send_command_byte(t, CMD_DISCONNECT);
		idle_clocks(t, 1);
		tb_assert(!t.get_stat_connected(), "Failed to disconnect\n");
	}

	return 0;
}