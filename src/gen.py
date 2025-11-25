import math
import numpy as np

def to_q16_16(x):
    """Convert float to signed 32-bit Q16.16."""
    return int(round(x * (1 << 16)))

print("module sine_rom_16_16 (")
print("    input  wire [7:0] addr,       ")
print("    output reg  signed [31:0] data")
print(");")
print()
print("    always @* begin")
print("        case (addr)")

# for i in range(360):
for index, i in enumerate(np.linspace(0, 360, num=256)):
    rad = math.radians(i)
    val = to_q16_16(math.sin(rad))
    # print(rad, math.sin(rad))
    print(f"            8'd{index}: data = 32'sh{val & 0xffffffff:08X}; // {val:8d} -> sin({i}°)")

print("            default: data = 32'sh00000000;")
print("        endcase")
print("    end")
print("endmodule")

