# smart_speed_update.py
# Adjusts G-code speeds for layers above the first if they are too slow

input_file = "input.gcode"
output_file = "output.gcode"

target_speed_mm_s = 75
target_speed_mm_min = target_speed_mm_s * 60  # convert to mm/min

current_layer = 0

with open(input_file, "r") as infile, open(output_file, "w") as outfile:
    for line in infile:
        # Detect layer changes
        if line.startswith(";LAYER:"):
            current_layer = int(line.strip().split(":")[1])

        # Only modify after first layer
        if current_layer > 0 and line.startswith("G1") and "F" in line:
            parts = line.split()
            for i, part in enumerate(parts):
                if part.startswith("F"):
                    try:
                        current_speed = float(part[1:])
                        if current_speed < target_speed_mm_min:
                            parts[i] = f"F{target_speed_mm_min:.0f}"
                    except ValueError:
                        pass
            line = " ".join(parts) + "\n"

        outfile.write(line)

print(f"✅ Done! Updated G-code saved to '{output_file}'")
