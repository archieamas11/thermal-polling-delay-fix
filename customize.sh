#!/system/bin/sh
MODDIR="${MODPATH}"

NEW_DELAY="5000"

# UI helpers
ui_info()  { ui_print "[*] $1"; }
ui_ok()    { ui_print "[✓] $1"; }
ui_warn()  { ui_print "[!] $1"; }
ui_die()   { ui_print "[✗] $1"; abort; }

if ! command -v set_perm >/dev/null 2>&1; then
  ui_die "set_perm not available — unsupported installer environment."
fi

if [ ! -d /data/adb/modules/mountify ]; then
  ui_warn "Mountify module not detected in /data/adb/modules/."
  ui_warn "Without Mountify the overlay will NOT bind-mount on boot."
  ui_warn "Install Mountify after this module, then reboot."
fi

ui_print ""
ui_print "================================================"
ui_print "   Thermal Skin Polling Fix — Installer"
ui_print "================================================"
ui_print ""
ui_info "Checking device compatibility..."

DEVICE=$(getprop ro.product.device)
ui_info "Detected device: ${DEVICE}"

case "${DEVICE}" in
  cheetah|lynx|panther)
    FAMILY="Tensor G2"
    SENSORS="VIRTUAL-SKIN VIRTUAL-SKIN-CHARGE VIRTUAL-SKIN-CPU VIRTUAL-SKIN-CPU-GPU VIRTUAL-SKIN-HINT"
    CHARGE_SENSORS="VIRTUAL-SKIN-CHARGE"
    ;;
  shiba|husky|akita)
    FAMILY="Tensor G3"
    SENSORS="VIRTUAL-SKIN VIRTUAL-SKIN-CPU-MID VIRTUAL-SKIN-CPU-HIGH VIRTUAL-SKIN-CPU-LIGHT-ODPM VIRTUAL-SKIN-GPU VIRTUAL-SKIN-SOC VIRTUAL-SKIN-HINT"
    CHARGE_SENSORS=""
    ;;
  *)
    ui_warn "Your device '${DEVICE}' is not supported."
    ui_warn "Supported devices: Pixel 7,8 Series only."
    ui_die  "Installation aborted — unsupported device."
    ;;
esac

ui_ok "Device check passed — ${FAMILY} (${DEVICE})"
ui_info "Target sensors (thermal_info_config.json):"
for S in ${SENSORS}; do
  ui_info "  • ${S}"
done
if [ -n "${CHARGE_SENSORS}" ]; then
  ui_info "Target sensors (thermal_info_config_charge.json):"
  for S in ${CHARGE_SENSORS}; do
    ui_info "  • ${S}"
  done
fi

TOTAL_PATCHED=0
TOTAL_SKIPPED=0

patch_sensor_in_file() {
  _file="$1"
  _sensor="$2"
  ui_info "  Patching ${_sensor} → PollingDelay=${NEW_DELAY}ms..."

  _tmp="${_file}.tmp"

  # Exit codes: 0=patched, 2=sensor not found, 3=found but no PollingDelay in window.
  awk -v name="${_sensor}" -v new="${NEW_DELAY}" '
    BEGIN {
      # Exact match avoids prefix collision (VIRTUAL-SKIN vs VIRTUAL-SKIN-CPU).
      pat = "\"Name\"[[:space:]]*:[[:space:]]*\"" name "\""
      in_block = 0
      countdown = 0
      done = 0
      matched = 0
    }
    {
      if (!done && $0 ~ pat) {
        in_block = 1
        countdown = 40
        matched = 1
      }
      if (in_block && countdown > 0 && !done && /"PollingDelay"/) {
        sub(/[0-9]+/, new)
        done = 1
        in_block = 0
      }
      if (in_block) countdown--
      print
    }
    END {
      if (!matched)   exit 2
      if (!done)      exit 3
      exit 0
    }
  ' "${_file}" > "${_tmp}"

  _rc=$?

  case "${_rc}" in
    0)
      if [ ! -s "${_tmp}" ]; then
        rm -f "${_tmp}"
        ui_warn "    ${_sensor}: awk produced empty output — skipped."
        return 1
      fi
      mv "${_tmp}" "${_file}"
      ui_ok "    ${_sensor}: patched"
      return 0
      ;;
    2)
      rm -f "${_tmp}"
      ui_warn "    ${_sensor}: not present — skipped."
      return 1
      ;;
    3)
      rm -f "${_tmp}"
      ui_warn "    ${_sensor}: found but no PollingDelay within block — skipped."
      return 1
      ;;
    *)
      rm -f "${_tmp}"
      ui_warn "    ${_sensor}: awk failed (rc=${_rc}) — skipped."
      return 1
      ;;
  esac
}

verify_sensor_in_file() {
  _file="$1"
  _sensor="$2"
  awk -v name="${_sensor}" '
    BEGIN {
      pat = "\"Name\"[[:space:]]*:[[:space:]]*\"" name "\""
      in_block = 0
      countdown = 0
    }
    {
      if ($0 ~ pat) { in_block = 1; countdown = 40 }
      if (in_block && countdown > 0 && /"PollingDelay"/) {
        match($0, /[0-9]+/)
        print substr($0, RSTART, RLENGTH)
        exit
      }
      if (in_block) countdown--
    }
  ' "${_file}"
}

process_config_file() {
  _src="$1"
  _dest="$2"
  _sensor_list="$3"
  _required="$4" 

  ui_print ""
  ui_info "Processing: ${_src}"

  if [ ! -f "${_src}" ]; then
    if [ "${_required}" = "required" ]; then
      ui_warn "Could not find: ${_src}"
      ui_die  "Source thermal config missing — cannot continue."
    else
      ui_warn "Optional config not present: ${_src} — skipping."
      return 0
    fi
  fi

  if [ ! -r "${_src}" ]; then
    ui_die "Source not readable: ${_src}"
  fi

  _src_size=$(wc -c < "${_src}" 2>/dev/null)
  if [ -z "${_src_size}" ] || [ "${_src_size}" -lt 100 ]; then
    ui_die "Source looks empty or truncated: ${_src} (size=${_src_size})."
  fi

  # Inherit source SELinux ctx — prevents denials on ROMs with non-default labels.
  _src_ctx=$(ls -Zd "${_src}" 2>/dev/null | awk '{print $1}')
  case "${_src_ctx}" in
    u:object_r:*:s0) : ;;
    *) _src_ctx="u:object_r:vendor_configs_file:s0" ;;
  esac

  ui_ok "Found: ${_src} (${_src_size} bytes, ctx=${_src_ctx})"

  mkdir -p "$(dirname "${_dest}")"
  cp "${_src}" "${_dest}"
  if [ $? -ne 0 ] || [ ! -f "${_dest}" ]; then
    ui_die "Failed to copy ${_src} to overlay."
  fi
  ui_ok "Copied to overlay: ${_dest}"

  _patched=0
  _skipped=0
  for _sensor in ${_sensor_list}; do
    if patch_sensor_in_file "${_dest}" "${_sensor}"; then
      _patched=$((_patched + 1))
    else
      _skipped=$((_skipped + 1))
    fi
  done

  if [ "${_patched}" -eq 0 ]; then
    ui_die "No sensors patched in ${_dest} — aborting to avoid shipping an unmodified overlay."
  fi

  ui_ok "Patched ${_patched} sensor(s); skipped ${_skipped} in $(basename "${_dest}")."

  # --- Validation ---
  ui_info "Validating patched overlay..."

  _out_size=$(wc -c < "${_dest}" 2>/dev/null)
  if [ -z "${_out_size}" ] || [ "${_out_size}" -lt 100 ]; then
    ui_die "Patched file is empty/truncated (size=${_out_size})."
  fi

  _min_size=$((_src_size * 3 / 4))
  _max_size=$((_src_size * 5 / 4))
  if [ "${_out_size}" -lt "${_min_size}" ] || [ "${_out_size}" -gt "${_max_size}" ]; then
    ui_die "Patched file size (${_out_size}) out of bounds vs source (${_src_size}). Aborting."
  fi

  # Balanced braces/brackets → catch truncation or mid-file corruption.
  _ob=$(tr -cd '{' < "${_dest}" | wc -c)
  _cb=$(tr -cd '}' < "${_dest}" | wc -c)
  _obk=$(tr -cd '[' < "${_dest}" | wc -c)
  _cbk=$(tr -cd ']' < "${_dest}" | wc -c)

  if [ "${_ob}" != "${_cb}" ]; then
    ui_die "JSON brace mismatch ({=${_ob}, }=${_cb}). Aborting."
  fi
  if [ "${_obk}" != "${_cbk}" ]; then
    ui_die "JSON bracket mismatch ([=${_obk}, ]=${_cbk}). Aborting."
  fi

  # Sensor count must match source — no blocks added/lost.
  _src_sensors=$(grep -c '"Name"[[:space:]]*:' "${_src}")
  _out_sensors=$(grep -c '"Name"[[:space:]]*:' "${_dest}")
  if [ "${_src_sensors}" != "${_out_sensors}" ]; then
    ui_die "Sensor count changed (src=${_src_sensors}, out=${_out_sensors}). Aborting."
  fi

  ui_ok "Overlay structurally intact (${_out_size} bytes, ${_out_sensors} sensors)."

  # --- Verify patched values ---
  ui_info "Verifying patched values..."
  for _sensor in ${_sensor_list}; do
    _val=$(verify_sensor_in_file "${_dest}" "${_sensor}")
    if [ -z "${_val}" ]; then
      ui_warn "  ${_sensor}: not found (skipped earlier)"
    elif [ "${_val}" = "${NEW_DELAY}" ]; then
      ui_ok   "  ${_sensor}: PollingDelay=${_val}ms"
    else
      ui_warn "  ${_sensor}: PollingDelay=${_val}ms (expected ${NEW_DELAY}ms)"
    fi
  done

  ui_info "Setting file permissions..."
  set_perm "${_dest}" root root 0644 "${_src_ctx}"
  ui_ok "Permissions set (0644, ctx=${_src_ctx})"

  TOTAL_PATCHED=$((TOTAL_PATCHED + _patched))
  TOTAL_SKIPPED=$((TOTAL_SKIPPED + _skipped))
  return 0
}

# --- Main: process the base thermal config, then the charge config on G2 -
process_config_file \
  "/vendor/etc/thermal_info_config.json" \
  "${MODDIR}/system/vendor/etc/thermal_info_config.json" \
  "${SENSORS}" \
  "required"

if [ -n "${CHARGE_SENSORS}" ]; then
  # Charge config is optional: some ROM builds may not ship it. If it's
  # missing we warn and move on rather than aborting the whole install.
  process_config_file \
    "/vendor/etc/thermal_info_config_charge.json" \
    "${MODDIR}/system/vendor/etc/thermal_info_config_charge.json" \
    "${CHARGE_SENSORS}" \
    "optional"
fi

ui_print ""
ui_print "================================================"
ui_ok   "Installation complete!"
ui_print ""
ui_info "Device : ${DEVICE} (${FAMILY})"
ui_info "Total  : ${TOTAL_PATCHED} sensor(s) patched, ${TOTAL_SKIPPED} skipped."
ui_info "Files  :"
ui_info "   • /vendor/etc/thermal_info_config.json"
if [ -n "${CHARGE_SENSORS}" ]; then
  ui_info "   • /vendor/etc/thermal_info_config_charge.json"
fi
ui_info "Change : PollingDelay → ${NEW_DELAY}ms on listed sensors."
ui_print ""
ui_info "Mountify will bind-mount the patched files at boot."
ui_info "No other sensors or values were modified."
ui_print "================================================"
ui_print ""
