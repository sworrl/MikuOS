// MikuOS Web Installer - device / safety constants.
// Everything here is a deliberate, reviewable decision. Read the comments before changing.

export const CONFIG = {
  // ---------------------------------------------------------------------------
  // TODO (MAINTAINER): fill this in from a real device:
  //     adb reboot bootloader && fastboot getvar product
  // The installer REFUSES to flash unless `getvar product` matches one of these
  // strings exactly (case-insensitive). While this is still the placeholder the
  // installer stays locked and prints the observed value in the log so you can
  // copy it here. Likely candidates for the HiBy M500 (SM6225 "bengal"):
  // "bengal", "M500", "su200", "M500_MIKU_4G" - but DO NOT guess; verify.
  // ---------------------------------------------------------------------------
  // Bootloader `product` for the HiBy M500 — CONFIRMED live 2026-08-29 via `fastboot getvar product`
  // (Qualcomm SM6225 "khaje" platform codename; build.prop device/name is m500_mikuOS on MikuOS).
  EXPECTED_PRODUCTS: ["khaje"],

  // Real `super` partition size on M500_MIKU_4G (fastboot getvar partition-size:super).
  // The MikuOS bundle is built to exactly this size; a mismatch means wrong image or wrong device.
  EXPECTED_SUPER_SIZE: 5371461632,

  // The M500's USB gadget wedges (device-side, needs a physical power-cycle) when super is
  // streamed in large bulk pushes. `fastboot -S 64M flash super` is the proven-good setting,
  // so every sparse payload we upload is capped at 64 MiB INCLUDING sparse headers.
  MAX_PAYLOAD_BYTES: 64 * 1024 * 1024,
  // Data bytes per chunk (headers fit in the remaining 1 MiB even in the worst case of
  // alternating zero / non-zero 4 KiB blocks). Must match `chunk_size` in release.json,
  // which make_release_manifest.py emits with the same default.
  DEFAULT_CHUNK_BYTES: 63 * 1024 * 1024,

  // Images at or below this size are sent as ONE raw payload (exactly what the proven
  // shell scripts do for boot/init_boot/dtbo/vendor_boot/vbmeta: plain `fastboot flash`
  // with no -S). Anything bigger goes through the chunked sparse path.
  // Also capped by the bootloader's max-download-size at run time.
  RAW_SINGLE_PAYLOAD_LIMIT: 128 * 1024 * 1024,

  BLOCK_SIZE: 4096,

  // Retry policy for a single chunk (the proven script retries the whole super once after 3 s).
  CHUNK_RETRIES: 3,
  RETRY_DELAY_MS: 3000,
  // If a payload makes no progress for this long the gadget is almost certainly wedged.
  STALL_TIMEOUT_MS: 90 * 1000,

  // Where to load the release manifest from (relative to index.html). Override with ?manifest=URL.
  MANIFEST_URL: "release.json",

  // Fastboot USB identity of the M500 (observed on the real device: 18d1:d00d).
  USB_VENDOR_ID: 0x18d1,
  USB_PRODUCT_ID: 0xd00d,

  // Recommended minimum state-of-charge before starting. Fastboot mode does NOT charge the
  // M500 and a full install takes ~10 minutes of sustained USB traffic.
  MIN_BATTERY_PERCENT: 50,
  // Qualcomm ABL exposes `battery-voltage` (mV). Rough single-cell Li-ion mapping used only
  // for a hint; the user still has to confirm the on-screen percentage they saw before rebooting.
  BATTERY_MV_HINT: [[4200, 100], [4100, 90], [4000, 75], [3900, 55], [3800, 40], [3700, 20], [3600, 5]],
};

// Partition -> manifest image key sequences, DERIVED from the repo's proven scripts.
// (mikuos/build/flash_mikuos_keepdata.sh, flash_mikuos_clean.sh, enable_root.sh,
//  disable_root.sh, tools/unbrick_factory.sh). Order matters and is preserved verbatim:
// boot-class partitions first (they rarely wedge), super last, so a super wedge never
// forces re-flashing the small ones.
export const BOOT_CHAIN = [
  ["boot_a", "boot"], ["boot_b", "boot"],
  ["init_boot_a", "init_boot"], ["init_boot_b", "init_boot"],
  ["dtbo_a", "dtbo"], ["dtbo_b", "dtbo"],
  ["vendor_boot_a", "vendor_boot"], ["vendor_boot_b", "vendor_boot"],
];
export const VBMETA_DISABLED = [
  ["vbmeta_a", "vbmeta_disabled"], ["vbmeta_b", "vbmeta_disabled"],
  ["vbmeta_system_a", "vbmeta_system_disabled"], ["vbmeta_system_b", "vbmeta_system_disabled"],
];
export const VBMETA_STOCK = [
  ["vbmeta_a", "vbmeta_stock"], ["vbmeta_b", "vbmeta_stock"],
  ["vbmeta_system_a", "vbmeta_system_stock"], ["vbmeta_system_b", "vbmeta_system_stock"],
];

// Images every MikuOS install needs. Optional keys: init_boot_rooted, stock_super,
// vbmeta_stock, vbmeta_system_stock, userdata_formatted.
export const REQUIRED_IMAGES = [
  "boot", "init_boot", "dtbo", "vendor_boot",
  "vbmeta_disabled", "vbmeta_system_disabled", "mikuos_system_bundle",
];

export const ACTIONS = {
  install_keepdata: {
    title: "Install / Update MikuOS (keep data)",
    blurb: "The default update path. Flashes the boot chain, AVB-disabled vbmeta and the MikuOS super bundle. /data (music library, liked songs, history, accounts) is preserved.",
    danger: "low",
  },
  install_clean: {
    title: "Clean install (WIPES all data)",
    blurb: "Same as above, then erases misc, metadata and userdata (the fastboot -w equivalent). Everything on internal storage is lost. Use for a first install from stock or to recover from a broken /data.",
    danger: "high",
  },
  root: {
    title: "Enable root (Magisk)",
    blurb: "Flashes the Magisk-patched init_boot to both slots. Root lives entirely in init_boot's ramdisk, so nothing else changes and no data is lost. Requires init_boot_rooted in the release.",
    danger: "medium",
  },
  unroot: {
    title: "Disable root (stock init_boot)",
    blurb: "Flashes the stock init_boot to both slots. Reverts 'Enable root'. No data is lost.",
    danger: "low",
  },
  rollback_stock: {
    title: "Rollback to stock HiBy firmware (WIPES all data)",
    blurb: "Restores the stock boot chain, the ORIGINAL signed vbmeta images and the stock super, then wipes data. Only available when the release ships stock_super + vbmeta_stock + vbmeta_system_stock.",
    danger: "high",
  },
};
