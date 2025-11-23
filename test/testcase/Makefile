TESTCASES := $(wildcard *.cpp)
TEST_EXCECS := $(addprefix build/,$(patsubst %.cpp,%,$(TESTCASES)))
TESTS_RUN := $(addprefix run.,$(patsubst %.cpp,%,$(TESTCASES)))

INCDIR := $(shell yosys-config --datdir)/include/backends/cxxrtl/runtime ../include

.PHONY: all clean
.SECONDARY:
all: $(TESTS_RUN)

build/%: %.cpp ../tb/tb.o ../include/twd_util.h
	mkdir -p build
	clang++ -O3 -std=c++14 -Wall $(addprefix -I,$(INCDIR)) $< ../tb/tb.o -o $@

run.%: build/%
	./$<

# Bit of a hack to trigger tb rebuild when verilog or testbench changes
../tb/tb.o: ../tb/tb.cpp ../include/tb.h $(shell find ../.. -name "*.v")
	make -C ../tb

clean:
	make -C ../tb clean
	rm -rf build
