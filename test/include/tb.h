#pragma once

#include <string>
#include <cstdint>
#include <fstream>
#include <backends/cxxrtl/cxxrtl.h>
#include <backends/cxxrtl/cxxrtl_vcd.h>

struct bus_read_response {
	uint32_t data;
	int delay_cycles;
	bool err;
};

struct bus_write_response {
	int delay_cycles;
	bool err;
};

typedef bus_read_response (*bus_read_callback)(uint64_t addr);

typedef bus_write_response (*bus_write_callback)(uint64_t addr, uint32_t data);

class tb {
public:
	tb(std::string vcdfile);
	void set_bus_read_callback(bus_read_callback cb);
	void set_bus_write_callback(bus_write_callback cb);

	void set_dck(bool dck);
	void set_di(bool di);
	bool get_do();
	bool get_stat_connected();
	void step();
private:
	int vcd_sample;
	bool dck_prev;
	bus_read_callback read_callback;
	bus_read_response last_read_response;
	bus_write_callback write_callback;
	bus_write_response last_write_response;
	std::ofstream waves_fd;
	cxxrtl::vcd_writer vcd;
	cxxrtl::module *dut;
};

#define tb_assert(cond, ...) if (!(cond)) {printf(__VA_ARGS__); exit(-1);}
