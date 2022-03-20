#!/usr/bin/env python3

def lfsr(width, poly):
	def f(state):
		feedback = state & poly
		state = (state << 1) & ((1 << width) - 1)
		for i in range(width):
			state ^= (feedback >> i) & 1
		return state
	return f

lfsr5 = lfsr(5, 0x14)
lfsr6 = lfsr(6, 0x30)
lfsr7 = lfsr(7, 0x60)

def lfsr_to_bytes(lfsr, state, statewidth, nbytes):
	l = []
	for i in range(nbytes):
		accum = 0
		for j in range(8):
			accum = (accum << 1) | (state >> statewidth - 1)
			state = lfsr(state)
		l.append(accum)
	return bytes(l)

print(", ".join(f"0x{x:02x}" for x in lfsr_to_bytes(lfsr6, 0x29, 6, 8)))
