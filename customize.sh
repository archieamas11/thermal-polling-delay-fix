#!/system/bin/sh
# =============================================================
#  Supported devices:
#    Tensor G2  : cheetah, lynx, panther
#    Tensor G3  : shiba,   husky, akita
# =============================================================

MODDIR="${MODPATH}"
THERMAL_SRC="/vendor/etc/thermal_info_config.json"
OVERLAY_DEST="${MODDIR}/system/vendor/etc/thermal_info_config.json"

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

# List of supported devices and their sensors
case "${DEVICE}" in
  cheetah|lynx|panther)
    FAMILY="Tensor G2"
    SENSORS="VIRTUAL-SKIN VIRTUAL-SKIN-CHARGE VIRTUAL-SKIN-CPU VIRTUAL-SKIN-CPU-GPU VIRTUAL-SKIN-HINT"
    ;;
  shiba|husky|akita)
    FAMILY="Tensor G3"
    SENSORS="VIRTUAL-SKIN-CPU-LIGHT-ODPM VIRTUAL-SKIN-CPU-MID VIRTUAL-SKIN-CPU-HIGH VIRTUAL-SKIN-SOC"
    ;;
  *)
    ui_warn "Your device '${DEVICE}' is not supported."
    ui_warn "Supported devices: Pixel 7,8 Series only."
    ui_die  "Installation aborted — unsupported device."
    ;;
esac

ui_ok "Device check passed — ${FAMILY} (${DEVICE})"
ui_info "Target sensors:"
for S in ${SENSORS}; do
  ui_info "  • ${S}"
done

# Verify source file exists
ui_info "Locating thermal config on device..."

if [ ! -f "${THERMAL_SRC}" ]; then
  ui_warn "Could not find: ${THERMAL_SRC}"
  ui_die  "Source thermal config missing — cannot continue."
fi

if [ ! -r "${THERMAL_SRC}" ]; then
  ui_die "Source thermal config not readable: ${THERMAL_SRC}"
fi

SRC_SIZE=$(wc -c < "${THERMAL_SRC}" 2>/dev/null)
if [ -z "${SRC_SIZE}" ] || [ "${SRC_SIZE}" -lt 100 ]; then
  ui_die "Source thermal config looks empty or truncated (size=${SRC_SIZE})."
fi

# Inherit source SELinux ctx — prevents denials on ROMs with non-default labels.
SRC_CTX=$(ls -Zd "${THERMAL_SRC}" 2>/dev/null | awk '{print $1}')
case "${SRC_CTX}" in
  u:object_r:*:s0) : ;;
  *) SRC_CTX="u:object_r:vendor_configs_file:s0" ;;
esac

ui_ok "Found: ${THERMAL_SRC} (${SRC_SIZE} bytes, ctx=${SRC_CTX})"
ui_info "Copying thermal config into module overlay..."

mkdir -p "$(dirname "${OVERLAY_DEST}")"
cp "${THERMAL_SRC}" "${OVERLAY_DEST}"

if [ $? -ne 0 ] || [ ! -f "${OVERLAY_DEST}" ]; then
  ui_die "Failed to copy thermal config to module directory."
fi

ui_ok "Copied to overlay path"

patch_sensor() {
  sensor="$1"
  ui_info "Patching ${sensor} → PollingDelay=${NEW_DELAY}ms..."

  TMP="${OVERLAY_DEST}.tmp"

  # Exit codes: 0=patched, 2=sensor not found, 3=found but no PollingDelay in window.
  awk -v name="${sensor}" -v new="${NEW_DELAY}" '
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
  ' "${OVERLAY_DEST}" > "${TMP}"

  rc=$?

  case "${rc}" in
    0)
      if [ ! -s "${TMP}" ]; then
        rm -f "${TMP}"
        ui_warn "  ${sensor}: awk produced empty output — skipped."
        return 1
      fi
      mv "${TMP}" "${OVERLAY_DEST}"
      ui_ok "  ${sensor}: patched"
      return 0
      ;;
    2)
      rm -f "${TMP}"
      ui_warn "  ${sensor}: not present in thermal config — skipped."
      return 1
      ;;
    3)
      rm -f "${TMP}"
      ui_warn "  ${sensor}: found but no PollingDelay within block — skipped."
      return 1
      ;;
    *)
      rm -f "${TMP}"
      ui_warn "  ${sensor}: awk failed (rc=${rc}) — skipped."
      return 1
      ;;
  esac
}

PATCHED_COUNT=0
SKIPPED_COUNT=0
for SENSOR in ${SENSORS}; do
  if patch_sensor "${SENSOR}"; then
    PATCHED_COUNT=$((PATCHED_COUNT + 1))
  else
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  fi
done

if [ "${PATCHED_COUNT}" -eq 0 ]; then
  ui_die "No sensors were patched — aborting to avoid shipping an unmodified overlay."
fi

ui_ok "Patched ${PATCHED_COUNT} sensor(s); skipped ${SKIPPED_COUNT}."

# Broken JSON over /vendor/etc/ can make thermal HAL fail parsing.
ui_info "Validating patched overlay..."

OUT_SIZE=$(wc -c < "${OVERLAY_DEST}" 2>/dev/null)
if [ -z "${OUT_SIZE}" ] || [ "${OUT_SIZE}" -lt 100 ]; then
  ui_die "Patched file is empty/truncated (size=${OUT_SIZE})."
fi

# Digits-only sub changes size by few bytes per sensor. ±25% = generous guard.
MIN_SIZE=$((SRC_SIZE * 3 / 4))
MAX_SIZE=$((SRC_SIZE * 5 / 4))
if [ "${OUT_SIZE}" -lt "${MIN_SIZE}" ] || [ "${OUT_SIZE}" -gt "${MAX_SIZE}" ]; then
  ui_die "Patched file size (${OUT_SIZE}) out of bounds vs source (${SRC_SIZE}). Aborting."
fi

# Balanced braces/brackets → catch truncation or mid-file corruption.
OPEN_BRACE=$(tr -cd '{' < "${OVERLAY_DEST}" | wc -c)
CLOSE_BRACE=$(tr -cd '}' < "${OVERLAY_DEST}" | wc -c)
OPEN_BRACK=$(tr -cd '[' < "${OVERLAY_DEST}" | wc -c)
CLOSE_BRACK=$(tr -cd ']' < "${OVERLAY_DEST}" | wc -c)

if [ "${OPEN_BRACE}" != "${CLOSE_BRACE}" ]; then
  ui_die "JSON brace mismatch ({=${OPEN_BRACE}, }=${CLOSE_BRACE}). Aborting."
fi
if [ "${OPEN_BRACK}" != "${CLOSE_BRACK}" ]; then
  ui_die "JSON bracket mismatch ([=${OPEN_BRACK}, ]=${CLOSE_BRACK}). Aborting."
fi

# Sensor count must match source — no blocks added/lost.
SRC_SENSORS=$(grep -c '"Name"[[:space:]]*:' "${THERMAL_SRC}")
OUT_SENSORS=$(grep -c '"Name"[[:space:]]*:' "${OVERLAY_DEST}")
if [ "${SRC_SENSORS}" != "${OUT_SENSORS}" ]; then
  ui_die "Sensor count changed (src=${SRC_SENSORS}, out=${OUT_SENSORS}). Aborting."
fi

ui_ok "Overlay structurally intact (${OUT_SIZE} bytes, ${OUT_SENSORS} sensors)."

# ── Verify each patched sensor ────────────────────────────
ui_info "Verifying patched values..."

verify_sensor() {
  sensor="$1"
  awk -v name="${sensor}" '
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
  ' "${OVERLAY_DEST}"
}

for SENSOR in ${SENSORS}; do
  VAL=$(verify_sensor "${SENSOR}")
  if [ -z "${VAL}" ]; then
    ui_warn "  ${SENSOR}: not found (skipped earlier)"
  elif [ "${VAL}" = "${NEW_DELAY}" ]; then
    ui_ok   "  ${SENSOR}: PollingDelay=${VAL}ms"
  else
    ui_warn "  ${SENSOR}: PollingDelay=${VAL}ms (expected ${NEW_DELAY}ms)"
  fi
done

ui_info "Setting file permissions..."
set_perm "${OVERLAY_DEST}" root root 0644 "${SRC_CTX}"
ui_ok "Permissions set (0644, ctx=${SRC_CTX})"

ui_print ""
ui_print "================================================"
ui_ok   "Installation complete!"
ui_print ""
ui_info "Device : ${DEVICE} (${FAMILY})"
ui_info "File   : /vendor/etc/thermal_info_config.json"
ui_info "Change : PollingDelay → ${NEW_DELAY}ms on:"
for S in ${SENSORS}; do
  ui_info "           • ${S}"
done
ui_print ""
ui_info "Mountify will bind-mount the patched file at boot."
ui_info "No other sensors or values were modified."
ui_print "================================================"
ui_print ""
