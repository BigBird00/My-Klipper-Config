# power_loss_recovery.py
#
# Drop-in Power Loss Recovery module for Klipper

import logging
import datetime

config_section = "power_loss_recovery"

class PowerLossRecovery:
    def __init__(self, config):
        self.debug_mode = True
        self.save_on_layer = True
        self.variables_file = "/home/ajs/printer_data/save_variables/variables.cfg"
    
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        self.gcode = self.printer.lookup_object('gcode')

        self.gcode.respond_info("PLR: __init__() executed")

        self.variables_file = config.get('variables_file',
                                         "/home/ajs/printer_data/SAVE_VARIABLES/variables.cfg")
        self.fan_object_name = config.get('fan_object', None)

        # core objects (initialized later)
        self.toolhead = None
        self.extruder = None
        self.heater_bed = None
        self.bed_mesh = None
        self.save_variables = None
        self.part_cooling_fan = None

        self.current_layer = 0

        # initialize core objects ONLY when Klipper is fully ready
        self.printer.register_event_handler("klippy:ready", self._on_printer_ready)

        # gcode commands
        self.gcode.register_command(
            "PLR_SAVE_PRINT_STATE_WITH_LAYER",
            self._handle_layer_change,
            desc="Save PLR state on layer change (requires L=<layer>)"
        )

        self.gcode.register_command(
            "PLR_SAVE_PRINT_STATE",
            self._manual_save,
            desc="Manual PLR save"
        )

    # ============================================================
    # printer ready
    # ============================================================

    def _on_printer_ready(self):
        self.toolhead = self.printer.lookup_object('toolhead')
        self.extruder = self.printer.lookup_object('extruder')
        self.heater_bed = self.printer.lookup_object('heater_bed', None)
        self.bed_mesh = self.printer.lookup_object('bed_mesh', None)
        self.save_variables = self.printer.lookup_object('save_variables')

        # optional fan object
        if self.fan_object_name:
            try:
                self.part_cooling_fan = self.printer.lookup_object(
                    self.fan_object_name, None)
            except Exception:
                self.part_cooling_fan = None
        else:
            for name in ('fan', 'part_cooling_fan'):
                obj = self.printer.lookup_object(name, None)
                if obj is not None:
                    self.part_cooling_fan = obj
                    break

        self.gcode.respond_info("PLR: Core objects initialized")

    # ============================================================
    # gcode handlers
    # ============================================================

    def _handle_layer_change(self, gcmd):
        if self.debug_mode:
            self.gcode.respond_info("PLR DEBUG: _handle_layer_change fired(A2)")
            self.gcode.respond_info("PLR DEBUG CMD: PLR_SAVE_PRINT_STATE_WITH_LAYER")
            self.gcode.respond_info(f"PLR DEBUG PARAM STR: {gcmd}")

        self.gcode.run_script("PLR_MARK_INTERRUPTED")
        eventtime = self.reactor.monotonic()
        print_stats = self.printer.lookup_object('print_stats')
        state = print_stats.get_status(eventtime).get('state')

        if self.debug_mode:
            self.gcode.respond_info(f"PLR DEBUG: print_stats.state={state}")

        # Accept PLR command even if state is standby or paused
        if state in ("complete", "error", "shutdown"):
            if self.debug_mode:
                self.gcode.respond_info("PLR DEBUG: print is complete/error, skipping PLR save")
            return

        # extract parameters from GCodeCommand
        layer = gcmd.get_int('L', None)
        slicer_z = gcmd.get_float('Z', 0.0)

        if layer is None:
            if self.debug_mode:
                self.gcode.respond_info("PLR DEBUG: no L parameter, skipping")
            return

        self.current_layer = layer
        self._save_current_state(layer, slicer_z)

    def _manual_save(self, gcmd):
        if self.debug_mode:
            self.gcode.respond_info("PLR: manual save requested")

        layer = self.current_layer
        self._save_current_state(layer)

    # ============================================================
    # state save / collect
    # ============================================================

    def _save_current_state(self, layer, slicer_z=None):
        self.gcode.respond_info(f"PLR DEBUG SAVE_VARIABLES type: {type(self.save_variables)}")

        if self.debug_mode:
            self.gcode.respond_info("PLR DEBUG: Entering _save_current_state")

        if not (self.toolhead and self.extruder and self.save_variables):
            self.gcode.respond_info("PLR: Core objects not ready, skipping save")
            return

        try:
            state = self._collect_current_state(layer)
        except Exception:
            logging.exception("PLR: Error collecting state")
            self.gcode.respond_info("PLR: Error collecting state")
            return

        if self.debug_mode:
            self.gcode.respond_info(f"PLR: Collected state: {state}")

        logging.info("PLR: _save_current_state @1")

        # SAVE_VARIABLE calls
        try:
            logging.info("PLR: _save_current_state @2")

            # last_file
            lf = repr(state['current_file'])
            self.gcode.run_script(
                f'SAVE_VARIABLE VARIABLE=last_file VALUE="{lf}"'
            )

            logging.info("PLR: _save_current_state @3")

            # full resume state dict
            rmi = repr(state)
            self.gcode.run_script(
                f'SAVE_VARIABLE VARIABLE=resume_meta_info VALUE="{rmi}"'
            )

            logging.info("PLR: _save_current_state @4")

            # interruption flag
            self.gcode.run_script(
                'SAVE_VARIABLE VARIABLE=was_interrupted VALUE="True"'
            )

            logging.info("PLR: _save_current_state @5")

        except Exception:
            logging.exception("PLR: Error saving to SAVE_VARIABLES")
            self.gcode.respond_info("PLR: Error saving to SAVE_VARIABLES")
            return

        self.gcode.respond_info("PLR: State saved to resume_meta_info")

    # ============================================================
    # collect state
    # ============================================================

    def _collect_current_state(self, layer):
        if self.debug_mode:
            self.gcode.respond_info("PLR DEBUG: Entering _collect_current_state")

        pos = self.toolhead.get_position()
        x, y, z, e = pos[0], pos[1], pos[2], pos[3]

        eventtime = self.reactor.monotonic()
        extruder_status = self.extruder.get_status(eventtime)
        hotend_temp = extruder_status.get('temperature')
        hotend_target = extruder_status.get('target')

        bed_temp = 0.0
        bed_target = 0.0
        if self.heater_bed is not None:
            bed_status = self.heater_bed.get_status(eventtime)
            bed_temp = bed_status.get('temperature', 0.0)
            bed_target = bed_status.get('target', 0.0)

        fan_speed = 0.0
        if self.part_cooling_fan is not None:
            try:
                status = self.part_cooling_fan.get_status(eventtime)
                fan_speed = status.get('speed', 0.0)
            except Exception:
                fan_speed = 0.0

        pressure_advance = getattr(self.extruder, 'pressure_advance', 0.0)

        mesh_data = None
        if self.bed_mesh is not None:
            try:
                mesh_status = self.bed_mesh.get_status()
                mesh_data = {
                    'profile': mesh_status.get('profile_name', None),
                    'mesh_min': mesh_status.get('mesh_min', None),
                    'mesh_max': mesh_status.get('mesh_max', None),
                }
            except Exception:
                mesh_data = None

        current_file = getattr(self.gcode, 'current_file', None)
        if current_file is None:
            current_file = 'unknown'

        state = {
            'current_file': current_file,
            'layer': int(layer),
            'position': {
                'x': x,
                'y': y,
                'z': z,
                'e': e,
            },
            'hotend_temp': float(hotend_temp),
            'bed_temp': float(bed_temp),
            'hotend_target': float(hotend_target),
            'bed_target': float(bed_target),
            'fan_speed': float(fan_speed),
            'pressure_advance': float(pressure_advance),
            'bed_mesh': mesh_data,
        }

        return state


def load_config(config):
    return PowerLossRecovery(config)
