#pragma once

// Convenience functions for interacting with the DTM testbench

#include "tb.h"

static inline void put_bits(tb &t, const uint8_t *tx, int n_bits) {
	uint8_t shifter;
	for (int i = 0; i < n_bits; ++i) {
		if (i % 8 == 0)
			shifter = tx[i / 8];
		else
			shifter <<= 1;
		t.set_di(shifter & 0x80u);
		t.step();
		t.set_dck(1);
		t.step();
		t.set_dck(0);
	}
}

static inline void get_bits(tb &t, uint8_t *rx, int n_bits) {
	uint8_t shifter;
	for (int i = 0; i < n_bits; ++i) {
		t.step();
		bool sample = t.get_do();
		t.set_di(sample);
		t.set_dck(1);
		t.step();
		t.set_dck(0);

		shifter = (shifter << 1) | sample;
		if (i % 8 == 7)
			rx[i / 8] = shifter;
	}
	if (n_bits % 8 != 0) {
		rx[n_bits / 8] = shifter << (8 - n_bits % 8);
	}
}

static inline void hiz_clocks(tb &t, int n_bits) {
	for (int i = 0; i < n_bits; ++i) {
		t.set_di(t.get_do());
		t.step();
		t.set_dck(1);
		t.step();
		t.set_dck(0);
	}
}

static inline void idle_clocks(tb &t, int n_bits) {
	t.set_di(0);
	for (int i = 0; i < n_bits; ++i) {
		t.step();
		t.set_dck(1);
		t.step();
		t.set_dck(0);
	}
}

static const uint8_t seq_connect_noaddr[] = {
	// Sync LFSR
	0x00,
	// 64 bits of LFSR output
	0xa7, 0xa3, 0x92, 0xdd, 0x9a, 0xbf, 0x04, 0x31
	// Then 4-bit address, followed by its complement
};

static inline void connect_target(tb &t, uint8_t addr) {
	put_bits(t, seq_connect_noaddr, 72);
	addr = (addr << 4) | (~addr & 0xfu);
	put_bits(t, &addr, 8);
}