#!/usr/bin/env python3

def lfsr6(state):
	return (
		(state >> 5 & 1) ^
		(state >> 4 & 1) ^
		state << 1
	) & 0x3f

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
