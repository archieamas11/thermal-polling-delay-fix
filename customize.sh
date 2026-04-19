#!/system/bin/sh
OVERLAY_FILE="${MODPATH}/system/vendor/etc/thermal_info_config.json"
TARGET_DEVICE="cheetah"

ui_info() { ui_print "[*] $1"; }
ui_ok()   { ui_print "[✓] $1"; }
ui_warn() { ui_print "[!] $1"; }
ui_die()  { ui_print "[✗] $1"; abort; }

ui_print ""
ui_print "================================================"
ui_print "   Thermal Skin Polling Fix v2.1 — Installer"
ui_print "================================================"
ui_print ""

ui_info "Checking device compatibility..."
DEVICE=$(getprop ro.product.device)
ui_info "Detected device: ${DEVICE}"

if [ "${DEVICE}" != "${TARGET_DEVICE}" ]; then
  ui_warn "This module targets Pixel 7 Pro (cheetah) only."
  ui_warn "Your device '${DEVICE}' is not supported."
  ui_die  "Aborting — wrong device."
fi
ui_ok "Device check passed (${DEVICE})"

ui_info "Verifying overlay file..."
if [ ! -f "${OVERLAY_FILE}" ]; then
  ui_die "Overlay JSON missing from module package — corrupted zip?"
fi
ui_ok "Overlay file present"

ui_info "Validating patched PollingDelay values..."
SENSORS="VIRTUAL-SKIN VIRTUAL-SKIN-HINT VIRTUAL-SKIN-CPU VIRTUAL-SKIN-CPU-GPU VIRTUAL-SKIN-CHARGE"
for NAME in $SENSORS; do
  LINE=$(grep -n "\"Name\":\"${NAME}\"" "${OVERLAY_FILE}" | head -1 | cut -d: -f1)
  if [ -z "${LINE}" ]; then
    LINE=$(grep -n "\"Name\": \"${NAME}\"" "${OVERLAY_FILE}" | head -1 | cut -d: -f1)
  fi
  if [ -z "${LINE}" ]; then
    ui_warn "Could not find sensor '${NAME}' — skipping check"
    continue
  fi
  VAL=$(awk -v start="${LINE}" '
    NR >= start && NR <= start+30 && /"PollingDelay"/ {
      match($0, /[0-9]+/)
      print substr($0, RSTART, RLENGTH)
      exit
    }
  ' "${OVERLAY_FILE}")
  if [ "${VAL}" = "5000" ]; then
    ui_ok "${NAME}: ${VAL}ms"
  else
    ui_warn "${NAME}: unexpected value ${VAL}ms"
  fi
done

ui_info "Setting file permissions..."
set_perm "${OVERLAY_FILE}" root root 0644 u:object_r:vendor_configs_file:s0
ui_ok "Permissions set"

ui_print ""
ui_print "================================================"
ui_ok   "Installation complete!"
ui_print ""
ui_info "Patched (300000ms → 5000ms):"
ui_info "  • VIRTUAL-SKIN          (primary skin sensor)"
ui_info "  • VIRTUAL-SKIN-CPU      (CPU throttling)"
ui_info "  • VIRTUAL-SKIN-CPU-GPU  (CPU+GPU throttling)"
ui_info "  • VIRTUAL-SKIN-CHARGE   (charge rate throttling)"
ui_info "  • VIRTUAL-SKIN-HINT     (power hint signals)"
ui_print ""
ui_info "Please reboot your device for changes to take effect. Mountify will bind-mount the overlay at boot."
ui_print "================================================"
ui_print ""
