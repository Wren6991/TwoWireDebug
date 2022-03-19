#include "tb.h"
#include "twd_util.h"

int main() {
	tb t("waves.vcd");
	connect_target(t, 0);
	return !t.get_stat_connected();
}