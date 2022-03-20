#pragma once

// Convenience functions for interacting with the DTM testbench

#include "tb.h"

// ----------------------------------------------------------------------------
// TWD constants

typedef enum {
	CMD_DISCONNECT = 0x0,
	CMD_R_IDCODE = 0x1,
	CMD_R_CSR = 0x2,
	CMD_W_CSR = 0x3,
	CMD_R_ADDR = 0x4,
	CMD_W_ADDR = 0x5,
	CMD_R_DATA = 0x7,
	CMD_R_BUFF = 0x8,
	CMD_W_DATA = 0x9
} twd_cmd;

static const uint8_t seq_connect_noaddr[] = {
	// Sync LFSR
	0x00,
	// 64 bits of LFSR output
	0xa7, 0xa3, 0x92, 0xdd, 0x9a, 0xbf, 0x04, 0x31,
	// 72 1s
	0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
	// Then 4-bit address, followed by its complement
};

static const unsigned CSR_MDROPADDR_LSB  = 4;
static const uint32_t CSR_MDROPADDR_BITS = 0x000000f0u;
static const unsigned CSR_ASIZE_LSB      = 24;
static const uint32_t CSR_ASIZE_BITS     = 0x0f000000u;

static inline uint32_t bytes_to_ule32(const uint8_t b[4]) {
	return (uint32_t)b[3] << 24 | b[2] << 16 | b[1] << 8 | b[0];
}

static inline void ule32_to_bytes(uint32_t u, uint8_t b[4]) {
	b[0] = u & 0xffu;
	b[1] = u >> 8 & 0xffu;
	b[2] = u >> 16 & 0xffu;
	b[3] = u >> 24 & 0xffu;
}

// ----------------------------------------------------------------------------
// Raw serial operations

// MSB-first wire order.
static inline void put_bits(tb &t, const uint8_t *tx, int n_bits) {
	uint8_t shifter;
	for (int i = 0; i < n_bits; ++i) {
		if (i % 8 == 0) {
			shifter = tx[i / 8];
			// If last byte contains less than 8 bits, we take its LSBs
			// (though still MSB-first order within that bit-group).
			if (n_bits - i < 8) {
				shifter <<= 8 - (n_bits - i);
			}
		}
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
		if (i % 8 == 7 || i == n_bits - 1)
			rx[i / 8] = shifter;
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

// ----------------------------------------------------------------------------
// DTM operations

static inline void connect_target(tb &t, uint8_t addr) {
	put_bits(t, seq_connect_noaddr, 144);
	addr = (addr << 4) | (~addr & 0xfu);
	put_bits(t, &addr, 8);
}

static inline void send_command_byte(tb &t, twd_cmd cmd) {
	uint8_t start_bit = 1;
	uint8_t parity = !(((uint8_t)cmd >> 3 ^ (uint8_t)cmd >> 2 ^ (uint8_t)cmd >> 1 ^ (uint8_t)cmd) & 0x1u);
	uint8_t turnaround = 0;
	put_bits(t, &start_bit, 1);
	put_bits(t, (uint8_t*)&cmd, 4);
	put_bits(t, &parity, 1);
	if (parity)
		put_bits(t, &turnaround, 2);
	else
		hiz_clocks(t, 2);
}

bool odd_parity(const uint8_t *data, int n_bits) {
	uint8_t accum = 1;
	for (int i = 0; i < n_bits; ++i) {
		accum ^= (data[i / 8] >> (i % 8)) & 0x1u;
	}
	return accum;
}

static inline void send_parity_byte(tb &t, const uint8_t *tx, int n_bits) {
	assert(n_bits % 8 == 0);
	uint8_t parity = odd_parity(tx, n_bits);
	// Parity, then 0, then 00 for turnaround
	parity <<= 3;
	put_bits(t, &parity, 4);
}

// returns true == ok
static inline bool check_parity_byte(tb &t, const uint8_t *rx, int n_bits) {
	assert(n_bits % 8 == 0);
	uint8_t parity;
	get_bits(t, &parity, 4);
	return parity == (odd_parity(rx, n_bits) << 3);
}

static inline void put_bits_with_parity(tb &t, const uint8_t *tx, int n_bits) {
	put_bits(t, tx, n_bits);
	send_parity_byte(t, tx, n_bits);
}

// returns true == good parity
bool read_csr(tb &t, uint32_t *csr) {
	uint8_t csrbytes[4];
	send_command_byte(t, CMD_R_CSR);
	get_bits(t, csrbytes, 32);
	*csr = bytes_to_ule32(csrbytes);
	return check_parity_byte(t, csrbytes, 32);
}

void write_csr(tb &t, uint32_t csr) {
	uint8_t csrbytes[4];
	ule32_to_bytes(csr, csrbytes);
	send_command_byte(t, CMD_W_CSR);
	put_bits_with_parity(t, csrbytes, 32);
}

void write_addr(tb &t, uint64_t addr, unsigned int asize) {
	uint8_t addr_bytes[8];
	ule32_to_bytes(addr, &addr_bytes[0]);
	ule32_to_bytes(addr >> 32, &addr_bytes[4]);
	send_command_byte(t, CMD_W_ADDR);
	put_bits_with_parity(t, addr_bytes, 8 * (asize + 1));
}

void write_data(tb &t, uint32_t data) {
	uint8_t data_bytes[4];
	ule32_to_bytes(data, data_bytes);
	send_command_byte(t, CMD_W_DATA);
	put_bits_with_parity(t, data_bytes, 32);
}

uint32_t read_data(tb &t) {
	uint8_t data_bytes[4];
	send_command_byte(t, CMD_R_DATA);
	get_bits(t, data_bytes, 32);
	return check_parity_byte(t, data_bytes, 32) ? bytes_to_ule32(data_bytes) : 0;
}

uint32_t read_buf(tb &t) {
	uint8_t data_bytes[4];
	send_command_byte(t, CMD_R_BUFF);
	get_bits(t, data_bytes, 32);
	return check_parity_byte(t, data_bytes, 32) ? bytes_to_ule32(data_bytes) : 0;
}
