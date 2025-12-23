export PLATFORM               = asap7

#  <--- ADD THIS LINE HERE:
export CLOCK_PERIOD           = 1500

export DESIGN_NICKNAME        = tritone
export DESIGN_NAME            = ternary_cpu_system

export VERILOG_FILES = $(sort $(wildcard $(DESIGN_HOME)/src/tritone/*.sv))

export VERILOG_INCLUDE_DIRS = $(DESIGN_HOME)/src/tritone

export SDC_FILE              = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/constraint.sdc

# Floorplan settings - relaxed for dual-issue CPU
export CORE_UTILIZATION       = 30
export CORE_ASPECT_RATIO      = 1
export CORE_MARGIN            = 2
export PLACE_DENSITY_LB_ADDON = 0.10

# Timing optimization
export TNS_END_PERCENT        = 100

# Allow large memories to synthesize as registers (for testing)
# Real ASIC would use SRAM macros
export SYNTH_MEMORY_MAX_BITS  = 50000