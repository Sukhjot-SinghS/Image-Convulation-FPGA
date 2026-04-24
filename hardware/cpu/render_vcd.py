import matplotlib.pyplot as plt
import re

# VCD Signal Mapping (Paths in tb_rv32m_alu.v)
# Signals are usually defined as:
# $var wire 1 ! clk $end
# $var wire 32 " pc_out [31:0] $end
# $var wire 1 # alu_busy $end
# ...

def parse_vcd(vcd_path, start_time, end_time):
    signals = {}
    symbol_map = {}
    
    with open(vcd_path, 'r') as f:
        # 1. Parse Definitions
        for line in f:
            if line.startswith('$var'):
                parts = line.split()
                symbol = parts[3]
                name = parts[4]
                symbol_map[symbol] = name
                signals[name] = {'times': [], 'values': []}
            if line.startswith('$enddefinitions'):
                break
        
        # 2. Parse Data
        curr_time = 0
        for line in f:
            line = line.strip()
            if not line: continue
            
            if line.startswith('#'):
                curr_time = int(line[1:])
                if curr_time > end_time: break
                continue
            
            if curr_time < start_time: continue
            
            # Value change
            if line[0] in '01zZ':
                val = line[0]
                symbol = line[1:]
                if symbol in symbol_map:
                    name = symbol_map[symbol]
                    signals[name]['times'].append(curr_time)
                    signals[name]['values'].append(int(val) if val in '01' else 0)
            elif line[0] == 'b':
                parts = line.split()
                val_str = parts[0][1:]
                symbol = parts[1]
                if symbol in symbol_map:
                    name = symbol_map[symbol]
                    signals[name]['times'].append(curr_time)
                    try:
                        signals[name]['values'].append(int(val_str, 2))
                    except:
                        signals[name]['values'].append(0)

    return signals

# Signals we want to plot (exact names from VCD)
# I'll check the symbol mapping first
def get_mapping(vcd_path):
    mapping = {}
    with open(vcd_path, 'r') as f:
        for line in f:
            if line.startswith('$var'):
                parts = line.split()
                mapping[parts[4]] = parts[3]
            if line.startswith('$enddefinitions'):
                break
    return mapping

m = get_mapping('rv32m_alu.vcd')
# Look for signals containing names. 
# We need: clk, pc_out, alu_busy, state, valid, counter
target_signals = {}
for name, sym in m.items():
    if name == 'clk': target_signals['clk'] = sym
    if 'pc_out' in name: target_signals['pc'] = sym
    if 'alu_busy' in name: target_signals['busy'] = sym
    if 'valid' in name and 'u_hw_math' in name: target_signals['valid'] = sym
    if 'state' in name and 'u_hw_math' in name: target_signals['state'] = sym
    if 'counter' in name and 'u_hw_math' in name: target_signals['counter'] = sym

# Find a DIV operation (busy high for a long time)
# I'll parse a window where I know stuff happens
# Based on earlier trace, 15/5 happens early.
# Let's try 10000ns to 20000ns
data = parse_vcd('rv32m_alu.vcd', 10000, 25000)

plt.figure(figsize=(12, 8))
keys = ['clk', 'pc', 'busy', 'state', 'counter', 'valid']
for i, key in enumerate(keys):
    if key in data:
        t = data[key]['times']
        v = data[key]['values']
        # Step function
        plt.subplot(len(keys), 1, i+1)
        plt.step(t, v, where='post')
        plt.ylabel(key)
        plt.grid(True, alpha=0.3)
        if i < len(keys)-1: plt.xticks([])

plt.tight_layout()
plt.savefig('rv32m_div_waveform.png', dpi=150)
print("Saved rv32m_div_waveform.png")
