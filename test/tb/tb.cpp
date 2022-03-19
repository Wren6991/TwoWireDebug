#include "tb.h"

#include <fstream>
#include <cstdint>

#include "dut.cpp"
#include <backends/cxxrtl/cxxrtl_vcd.h>

tb::tb(std::string vcdfile) {
	// Raw pointer... CXXRTL doesn't give us the type declaration wihout also
	// giving us non-inlined implementation, and I'm not very good at C++, so
	// we do this shit
	cxxrtl_design::p_twowire__dtm *dtm = new cxxrtl_design::p_twowire__dtm;
	dut = dtm;
 
	waves_fd.open(vcdfile);
	cxxrtl::debug_items all_debug_items;
	dtm->debug_info(all_debug_items);
	vcd.timescale(1, "us");
	vcd.add(all_debug_items);
	vcd_sample = 0;

	dtm->p_drst__n.set<bool>(false);
	dtm->step();
	dtm->p_drst__n.set<bool>(true);
	dtm->step();

	dck_prev = false;
	read_callback = NULL;
	write_callback = NULL;
	last_read_response.delay_cycles = 0;
	last_write_response.delay_cycles = 0;

	vcd.sample(vcd_sample++);
	waves_fd << vcd.buffer;
	vcd.buffer.clear();
}

void tb::set_bus_read_callback(bus_read_callback cb) {
	read_callback = cb;
}

void tb::set_bus_write_callback(bus_write_callback cb) {
	write_callback = cb;
}

void tb::set_dck(bool dck) {
	static_cast<cxxrtl_design::p_twowire__dtm*>(dut)->p_dck.set<bool>(dck);
}

void tb::set_di(bool di) {
	static_cast<cxxrtl_design::p_twowire__dtm*>(dut)->p_di.set<bool>(di);
}

bool tb::get_do() {
	// Pulldown on bus, so return 0 if pin tristated.
	return static_cast<cxxrtl_design::p_twowire__dtm*>(dut)->p_doe.get<bool>() ?
		static_cast<cxxrtl_design::p_twowire__dtm*>(dut)->p_do.get<bool>() : false;
}

bool tb::get_stat_connected() {
	return static_cast<cxxrtl_design::p_twowire__dtm*>(dut)->p_host__connected.get<bool>();
}

void tb::step() {
	cxxrtl_design::p_twowire__dtm *dtm = static_cast<cxxrtl_design::p_twowire__dtm*>(dut);

	uint64_t bus_addr = dtm->p_dst__paddr.get<uint64_t>();
	bool bus_setup_phase = dtm->p_dst__psel.get<bool>() && !dtm->p_dst__penable.get<bool>(); 
	bool bus_wen = bus_setup_phase && dtm->p_dst__pwrite.get<bool>();
	bool bus_ren = bus_setup_phase && !dtm->p_dst__pwrite.get<bool>();
	uint32_t bus_wdata = dtm->p_dst__pwdata.get<uint32_t>();

	dtm->step();
	dtm->step();
	vcd.sample(vcd_sample++);
	waves_fd << vcd.buffer;
	waves_fd.flush();
	vcd.buffer.clear();

	// Field bus accesses using testcase callbacks if available, and provide
	// bus responses with correct timing based on callback results.
	if (!dck_prev && dtm->p_dck.get<bool>()) {
		dtm->p_dst__pslverr.set<bool>(0);
		dtm->p_dst__pready.set<bool>(0);
		if (last_read_response.delay_cycles > 0) {
			--last_read_response.delay_cycles;
			if (last_read_response.delay_cycles == 0) {
				dtm->p_dst__prdata.set<uint32_t>(last_read_response.data);
				dtm->p_dst__pslverr.set<bool>(last_read_response.err);
				dtm->p_dst__pready.set<bool>(1);
			}
		}
		if (last_write_response.delay_cycles > 0) {
			--last_write_response.delay_cycles;
			if (last_write_response.delay_cycles == 0) {
				dtm->p_dst__pslverr.set<bool>(last_write_response.err);
				dtm->p_dst__pready.set<bool>(1);
			}
		}
		if (bus_ren && read_callback) {
			last_read_response = read_callback(bus_addr);
			// The test harness this was adapted from wasn't APB... consider
			// this a TODO until there are tests covering the downstream bus.
			last_read_response.delay_cycles++;

			// if (last_read_response.delay_cycles == 0) {
			// 	dtm->p_dst__prdata.set<uint32_t>(last_read_response.data);
			// 	dtm->p_dst__pslverr.set<bool>(last_read_response.err);
			// }
			// else {
			// 	dtm->p_dst__pready.set<bool>(0);
			// }
		}
		else if (bus_wen && write_callback) {
			last_write_response = write_callback(bus_addr, bus_wdata);
			last_read_response.delay_cycles++;
			// if (last_write_response.delay_cycles == 0) {
			// 	dtm->p_dst__pslverr.set<bool>(last_write_response.err);
			// }
			// else {
			// 	dtm->p_dst__pready.set<bool>(0);
			// }
		}
	}
	dck_prev = dtm->p_dck.get<bool>();
}
