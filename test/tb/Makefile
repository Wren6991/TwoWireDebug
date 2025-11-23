HDL = $(shell find ../.. -name "*.v")
TOP = twowire_dtm

INCDIR := $(shell yosys-config --datdir)/include/backends/cxxrtl/runtime ../include

.PHONY: clean all

all: tb.o

SYNTH_CMD += read_verilog $(HDL);
SYNTH_CMD += chparam -set IDCODE 32'hdeadbeef $(TOP);
SYNTH_CMD += chparam -set ASIZE  3            $(TOP);
SYNTH_CMD += hierarchy -top $(TOP);
SYNTH_CMD += write_cxxrtl dut.cpp;

dut.cpp: $(HDL)
	yosys -p "$(SYNTH_CMD)" 2>&1 > cxxrtl.log

tb.o: dut.cpp tb.cpp
	clang++ -O3 -std=c++14 -Wall $(addprefix -D,$(CDEFINES)) $(addprefix -I,$(INCDIR)) -c tb.cpp -o tb.o

clean::
	rm -f tb.o dut.cpp cxxrtl.log

