# power_loss_recovery.py
#
# Drop-in Power Loss Recovery module for Klipper
#
# Config section:
# [power_loss_recovery]
# variables_file: ~/printer_data/save_variables/variables.cfg
# fan_object: fan                         # optional; name of part cooling fan object
#

import logging

config_section = "power_loss_recovery"

class PowerLossRecovery:
    def __init__(self, config):
        self.debug_mode = True
        self.save_on_layer = True
        self.variables_file = "~/printer_data/save_variables/variables.cfg"
    
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        self.gcode = self.printer.lookup_object('gcode')

        self.gcode.respond_info("PLR: __init__() executed")
        
        self.debug_mode = True
        self.save_on_layer = True

        self.variables_file = config.get('variables_file',
                                         "~/printer_data/save_variables/variables.cfg")
        self.fan_object_name = config.get('fan_object', None)

        # --- core objects (initialized later) ---
        self.toolhead = None
        self.extruder = None
        self.heater_bed = None
        self.bed_mesh = None
        self.save_variables = None
        self.part_cooling_fan = None

        self.current_layer = 0

        self.gcode.respond_info("PLR: __init__() executed")

        # initialize core objects when printer is fully built
        self.printer.register_event_handler("klippy:connect",
                                            self._on_printer_ready)

        # --- gcode commands ---
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
    #     printer ready
    # these should not be needed
    def _on_printer_build(self):
        self.gcode.respond_info("PLR: klippy:printer_build_complete")

    def _on_klipper_ready(self):
        self.gcode.respond_info("PLR: klippy:ready")
    # end these should not be needed
    
    def _on_printer_ready(self):
        # core Klipper objects
        self.toolhead = self.printer.lookup_object('toolhead')
        self.extruder = self.printer.lookup_object('extruder')
        self.heater_bed = self.printer.lookup_object('heater_bed', None)
        self.bed_mesh = self.printer.lookup_object('bed_mesh', None)
        self.save_variables = self.printer.lookup_object('save_variables', None)

        # optional fan object
        if self.fan_object_name:
            try:
                self.part_cooling_fan = self.printer.lookup_object(
                    self.fan_object_name, None)
            except Exception:
                self.part_cooling_fan = None
        else:
            # try a few common names; harmless if None
            for name in ('fan', 'part_cooling_fan'):
                obj = self.printer.lookup_object(name, None)
                if obj is not None:
                    self.part_cooling_fan = obj
                    break

        self.gcode.respond_info("PLR: Core objects initialized")

    # ============================================================
    #     gcode handlers
    # ============================================================

    def _handle_layer_change(self, gcmd):
        if self.debug_mode:
            self.gcode.respond_info("PLR DEBUG: _handle_layer_change fired")

        eventtime = self.reactor.monotonic()
        print_stats = self.printer.lookup_object('print_stats')
        state = print_stats.get_status(eventtime).get('state')

        # state = self.printer.get_state()
        if state != 'printing':
            if self.debug_mode:
                self.gcode.respond_info(
                    f"PLR DEBUG: layer change received, state={state}")
            return

        # layer from macro: PLR_SAVE_PRINT_STATE_WITH_LAYER L=<layer>
        layer = gcmd.get_int('L', None)
        if layer is None:
            if self.debug_mode:
                self.gcode.respond_info("PLR DEBUG: no L parameter, skipping")
            return

        self.current_layer = layer
        self._save_current_state(layer)

    def _manual_save(self, gcmd):
        if self.debug_mode:
            self.gcode.respond_info("PLR: manual save requested")

        # use last known layer; if none, 0
        layer = self.current_layer
        self._save_current_state(layer)

    # ============================================================
    #     state save / collect
    # ============================================================

    def _save_current_state(self, layer):
        if self.debug_mode:
            self.gcode.respond_info("PLR DEBUG: Entering _save_current_state")

        if not (self.toolhead and self.extruder):
            self.gcode.respond_info("PLR: Core objects not ready, skipping save")
            return

        try:
            state = self._collect_current_state(layer)
        except Exception:
            logging.exception("PLR: Error collecting state")
            self.gcode.respond_info("PLR: Error collecting state")
            self.gcode.respond_info("PLR: No state collected")
            return

        if self.debug_mode:
            self.gcode.respond_info(f"PLR: Collected state: {state}")

        # write into save_variables
        if self.save_variables is not None:
            try:
                self.save_variables.set_var('last_file', state['current_file'])
                self.save_variables.set_var('resume_meta_info', state)
                # default: assume not interrupted unless you wire a real signal
                self.save_variables.set_var('was_interrupted', False)
            except Exception:
                logging.exception("PLR: Error saving to save_variables")
                self.gcode.respond_info("PLR: Error saving to save_variables")
                return

        self.gcode.respond_info("PLR: State saved")
        self.gcode.respond_info("PLR: State saved to resume_meta_info")

    def _collect_current_state(self, layer):
        if self.debug_mode:
            self.gcode.respond_info("PLR DEBUG: Entering _collect_current_state")

        # current position: [x, y, z, e]
        pos = self.toolhead.get_position()
        x, y, z, e = pos[0], pos[1], pos[2], pos[3]

        # temps and targets
        # hotend_temp = self.extruder.get_temp()
        # hotend_target = self.extruder.get_target_temp()

        eventtime = self.reactor.monotonic()
        extruder_status = self.extruder.get_status(eventtime)
        
        hotend_temp = extruder_status.get('temperature')
        hotend_target = extruder_status.get('target')


        bed_temp = 0.0
        bed_target = 0.0
        if self.heater_bed is not None:
            bed_temp = self.heater_bed.get_temp()
            bed_target = self.heater_bed.get_target_temp()

        # fan speed
        fan_speed = 0.0
        if self.part_cooling_fan is not None:
            try:
                status = self.part_cooling_fan.get_status()
                # many fan objects expose 'speed' in [0.0 .. 1.0]
                fan_speed = status.get('speed', 0.0)
            except Exception:
                fan_speed = 0.0

        # pressure advance
        pressure_advance = 0.0
        try:
            pressure_advance = getattr(self.extruder, 'pressure_advance', 0.0)
        except Exception:
            pressure_advance = 0.0

        # bed mesh info (optional)
        mesh_data = None
        if self.bed_mesh is not None:
            try:
                # get_status() is stable; get_mesh() is more detailed but may vary
                mesh_status = self.bed_mesh.get_status()
                mesh_data = {
                    'profile': mesh_status.get('profile_name', None),
                    'mesh_min': mesh_status.get('mesh_min', None),
                    'mesh_max': mesh_status.get('mesh_max', None),
                }
            except Exception:
                mesh_data = None

        # current file: from gcode object
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
