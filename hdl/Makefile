TARGETS = compile run clean

all: compile

compile: tb/tb_hello_world.sv
	iverilog -o testbench tb/tb_hello_world.sv

run: compile
	vvp testbench

clean:
	rm -f testbench *.vcd

.PHONY: $(TARGETS)