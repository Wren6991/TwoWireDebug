HDL = $(shell find ../.. -name "*.v")
TOP = twowire_dtm

INCDIR := $(shell yosys-config --datdir)/include ../include

.PHONY: clean all

all: tb.o

dut.cpp: $(HDL)
	yosys -p "read_verilog $(HDL); hierarchy -top $(TOP); write_cxxrtl dut.cpp" 2>&1 > cxxrtl.log

tb.o: dut.cpp tb.cpp
	clang++ -O3 -std=c++14 -Wall $(addprefix -D,$(CDEFINES)) $(addprefix -I,$(INCDIR)) -c tb.cpp -o tb.o

clean::
	rm -f tb.o dut.cpp cxxrtl.log

