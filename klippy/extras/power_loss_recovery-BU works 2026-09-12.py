# ============================================================
#   POWER LOSS RECOVERY — FINAL WORKING VERSION
# ============================================================

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
    
        # Core objects start as None
        self.toolhead = None
        self.extruder = None
        self.heater_bed = None
        self.bed_mesh = None
        self.save_variables = None
        self.part_cooling_fan = None

        # Register callback for when printer is fully ready
        # self.printer.register_event_handler("klippy:connect", self._on_printer_ready)

        self.printer.register_event_handler("klippy:printer_build_complete", self._on_printer_build)
        self.printer.register_event_handler("klippy:ready", self._on_klipper_ready)


        self.printer.register_event_handler("klippy:connect", self._on_printer_ready)

        # Register commands
        self.gcode.register_command(
            "PLR_SAVE_PRINT_STATE_WITH_LAYER",
            self._handle_layer_change,
            desc="Save PLR state on layer change"
        )

        self.gcode.register_command(
            "PLR_SAVE_PRINT_STATE",
            self._manual_save,
            desc="Manual PLR save"
        )
    # ============================================================
    #     on_printer_ready
    # ============================================================

    def _on_printer_build(self):
        self.gcode.respond_info("PLR: klippy:printer_build_complete")

    def _on_klipper_ready(self):
        self.gcode.respond_info("PLR: klippy:ready")

    def _on_printer_ready(self):
        self.toolhead = self.printer.lookup_object('toolhead')
        self.extruder = self.printer.lookup_object('extruder')
        self.heater_bed = self.printer.lookup_object('heater_bed', None)
        self.bed_mesh = self.printer.lookup_object('bed_mesh', None)
        self.save_variables = self.printer.lookup_object('save_variables', None)
    
        self.gcode.respond_info("PLR: Core objects initialized")

    # ============================================================
    #   MANUAL SAVE
    # ============================================================
    def _manual_save(self, gcmd):
        self.gcode.respond_info("PLR: manual save requested")
        self._save_current_state(gcmd)


    # ============================================================
    #   LAYER CHANGE HANDLER
    # ============================================================
    def _handle_layer_change(self, gcmd):
        self.gcode.respond_info("PLR DEBUG: _handle_layer_change fired")

        print_stats = self.printer.lookup_object('print_stats')
        status = print_stats.get_status(self.reactor.monotonic())
        state = status.get('state')

        self.gcode.respond_info(f"PLR DEBUG: layer change received, state={state}")

        # Allow early + normal printing states
        if state not in ("starting", "printing", "paused", "resumed"):
            gcmd.respond_info(f"PLR: Ignoring layer change, state={state}")
            return

        # Core readiness
        if not self.toolhead:
            gcmd.respond_info("PLR: Core object TOOLHEAD  not ready yet")
            return

        if not self.extruder:
            gcmd.respond_info("PLR: Core object EXTRUDER not ready yet")
            return

        if not self.toolhead or not self.extruder:
            gcmd.respond_info("PLR: Core objects not ready yet")
            return

        # Save state
        self._save_current_state(gcmd)

    # ============================================================
    #   COLLECT STATE
    # ============================================================
    def _collect_current_state(self, gcmd=None):
        self.gcode.respond_info("PLR DEBUG: Entering _collect_current_state")

        # Extract layer number
        layer = None
        if gcmd is not None:
            layer = gcmd.get_int('LAYER', None)
        if layer is None:
            layer = 0

        # Core readiness
        if not self.toolhead :
            if self.debug_mode:
                self.gcode.respond_info("PLR: Core object TOOLHEAD not ready, skipping state collection")
            return None

        if not self.extruder:
               if self.debug_mode:
                   self.gcode.respond_info("PLR: Core object EXTRUDER not ready, skipping state collection")
               return None

        if not self.toolhead or not self.extruder:
               if self.debug_mode:
                   self.gcode.respond_info("PLR: Core objects not ready, skipping state collection - Should never occur!")
               return None



        try:
            # Position
            pos = self.toolhead.get_position()
            x, y, z, e = pos

            # Extruder temps
            extruder_status = self.extruder.get_status(self.reactor.monotonic())
            extruder_temp = extruder_status.get('temperature')
            extruder_target = extruder_status.get('target')

            # Bed temps
            bed_status = self.heater_bed.get_status(self.reactor.monotonic()) if self.heater_bed else {}
            bed_temp = bed_status.get('temperature', 0.0)
            bed_target = bed_status.get('target', 0.0)

 
            # Fan speed
            fan_speed = 0.0
            if self.part_cooling_fan is not None:
                try:
                    fan_speed = self.part_cooling_fan.get_status(
                        self.reactor.monotonic()
                    ).get('speed', 0.0)
                except Exception:
                    fan_speed = 0.0

            # Pressure advance
            pa_value = 0.0
            try:
                pa_value = self.toolhead.get_status(
                    self.reactor.monotonic()
                ).get('pressure_advance', 0.0)
            except Exception:
                pa_value = 0.0

            # Bed mesh
            mesh_profile = None
            if self.bed_mesh is not None:
                try:
                    mesh_profile = self.bed_mesh.mesh
                except Exception:
                    mesh_profile = None

            # Current file
            current_file = self.printer.lookup_object('print_stats') \
                .get_status(self.reactor.monotonic()) \
                .get('filename', 'unknown')

            state = {
                "current_file": current_file,
                "layer": layer,
                "position": {"x": x, "y": y, "z": z, "e": e},
                "hotend_temp": extruder_temp,
                "bed_temp": bed_temp,
                "hotend_target": extruder_target,
                "bed_target": bed_target,
                "fan_speed": fan_speed,
                "pressure_advance": pa_value,
                "bed_mesh": mesh_profile,
            }

            if self.debug_mode:
                self.gcode.respond_info(f"PLR: Collected state: {state}")

            return state

        except Exception as e:
            logging.exception("PLR: Error collecting state")
            return None

    # ============================================================
    #   SAVE STATE
    # ============================================================
    def _save_current_state(self, gcmd=None):
        self.gcode.respond_info("PLR DEBUG: Entering _save_current_state")

        state = self._collect_current_state(gcmd)
        if state is None:
            self.gcode.respond_info("PLR: No state collected")
            return

        # Convert dict → Python literal
        state_literal = repr(state)

        # Save resume_meta_info
        save_meta = self.gcode.create_gcode_command(
            "SAVE_VARIABLE", "SAVE_VARIABLE",
            {"VARIABLE": "resume_meta_info", "VALUE": state_literal}
        )
        self.save_variables.cmd_SAVE_VARIABLE(save_meta)

        # Save last_file (must be quoted)
        filename = state.get("current_file", "none")
        save_last_file = self.gcode.create_gcode_command(
            "SAVE_VARIABLE", "SAVE_VARIABLE",
            {"VARIABLE": "last_file", "VALUE": f"'{filename}'"}
        )
        self.save_variables.cmd_SAVE_VARIABLE(save_last_file)

        # Mark interrupted
        save_interrupted = self.gcode.create_gcode_command(
            "SAVE_VARIABLE", "SAVE_VARIABLE",
            {"VARIABLE": "was_interrupted", "VALUE": "True"}
        )
        self.save_variables.cmd_SAVE_VARIABLE(save_interrupted)

        if gcmd:
            gcmd.respond_info("PLR: State saved")
        self.gcode.respond_info("PLR: State saved to resume_meta_info")

def load_config(config):
    return PowerLossRecovery(config)
