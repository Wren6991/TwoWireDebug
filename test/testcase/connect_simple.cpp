#include "tb.h"
#include "twd_util.h"

int main() {
	tb t("waves.vcd");
	connect_target(t, 0);
	idle_clocks(t, 1);
	tb_assert(t.get_stat_connected(), "Did not connect\n");
	return 0;
}