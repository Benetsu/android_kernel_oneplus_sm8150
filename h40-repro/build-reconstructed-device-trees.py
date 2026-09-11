#!/usr/bin/env python3
"""Build and verify the complete reconstructed H.40 DTB/DTBO payload."""

import argparse
import csv
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys


DT_TABLE_MAGIC = 0xD7B7AB1E
DT_TABLE_HEADER_SIZE = 32
DT_TABLE_ENTRY_SIZE = 32
DT_TABLE_PAGE_SIZE = 4096
STOCK_DTB_IMAGE_SHA256 = (
    "36f8cbbcf1fd393b8df397f69596069e715bf8da1603b0c8f5fd690005fcf7eb"
)
STOCK_DTBO_TABLE_SHA256 = (
    "ddf316ecd06a35b554cf66d0f217063490eccb9e297c4c51302ae03cb6cdafef"
)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_manifest(path):
    with path.open("r", encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def compile_dts(dtc, source, output, boot_cpuid_phys):
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        str(dtc),
        "-I", "dts",
        "-O", "dtb",
        "-H", "epapr",
        "-b", str(boot_cpuid_phys),
        "-o", str(output),
        str(source),
    ]
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(
            "DTC failed for {} (exit {})".format(source, result.returncode)
        )


def compile_entries(dtc, source_root, output_root, rows, mode, kind):
    compiled = []
    expected_key = "{}_sha256".format(mode)
    for row in rows:
        source = source_root / row["source"]
        output = output_root / kind / row["output"]
        boot_cpuid = int(row.get("boot_cpuid_phys") or 0)
        compile_dts(dtc, source, output, boot_cpuid)
        payload = output.read_bytes()
        digest = sha256(payload)
        expected = row[expected_key]
        if mode == "stock" and digest != expected:
            raise SystemExit(
                "{} hash mismatch: got {}, expected {}".format(
                    row["source"], digest, expected
                )
            )
        if mode == "stock" and len(payload) != int(row["stock_size"]):
            raise SystemExit(
                "{} size mismatch: got {}, expected {}".format(
                    row["source"], len(payload), row["stock_size"]
                )
            )
        compiled.append((row, payload, output, digest))
    return compiled


def pack_dtbo(entries):
    entries_offset = DT_TABLE_HEADER_SIZE
    payload_offset = entries_offset + DT_TABLE_ENTRY_SIZE * len(entries)
    packed_entries = []
    payloads = []
    cursor = payload_offset
    for row, payload, _output, _digest in entries:
        packed_entries.append(
            struct.pack(
                ">8I",
                len(payload),
                cursor,
                int(row["dt_id"]),
                int(row["dt_revision"]),
                int(row["custom0"]),
                int(row["custom1"]),
                int(row["custom2"]),
                int(row["custom3"]),
            )
        )
        payloads.append(payload)
        cursor += len(payload)
    header = struct.pack(
        ">8I",
        DT_TABLE_MAGIC,
        cursor,
        DT_TABLE_HEADER_SIZE,
        DT_TABLE_ENTRY_SIZE,
        len(entries),
        entries_offset,
        DT_TABLE_PAGE_SIZE,
        0,
    )
    return b"".join([header] + packed_entries + payloads)


def require_wave16_sources(source_root, rows):
    required = (
        'qcom,ddr-stats@c3f0000 {',
        'compatible = "qcom,h40-ddr-stats";',
        'reg = <0x00 0xc300000 0x00 0x100000',
        '0x00 0xc3f0014 0x00 0x04>;',
        'reg-names = "phys_addr_base", "offset_addr";',
    )
    for row in rows:
        source = source_root / row["source"]
        text = source.read_text(encoding="utf-8")
        is_rtic = row["project_id"] == "-"
        counts = [text.count(fragment) for fragment in required]
        expected = 0 if is_rtic else 1
        if counts != [expected] * len(required):
            raise SystemExit(
                "H.40 AOP DDR-stats invariant failed for {}: {}".format(
                    row["source"], counts
                )
            )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dtc", required=True, type=Path)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--mode", choices=("stock", "active"), default="active")
    parser.add_argument("--require-wave16-ddr-stats", action="store_true")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    source_root = args.source_root or (
        repo_root / "arch" / "arm64" / "boot" / "dts" / "h40-reconstructed"
    )
    base_rows = read_manifest(source_root / "boot-fdt-manifest.tsv")
    overlay_rows = read_manifest(source_root / "overlay-manifest.tsv")
    if [int(row["index"]) for row in base_rows] != list(range(1, 26)):
        raise SystemExit("boot-FDT manifest must contain ordered indices 1..25")
    if [int(row["index"]) for row in overlay_rows] != list(range(15)):
        raise SystemExit("overlay manifest must contain ordered indices 0..14")
    if args.require_wave16_ddr_stats:
        require_wave16_sources(source_root, base_rows)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    base = compile_entries(
        args.dtc, source_root, args.out_dir, base_rows, args.mode, "base"
    )
    overlays = compile_entries(
        args.dtc, source_root, args.out_dir, overlay_rows, args.mode, "overlays"
    )

    dtb_image = b"".join(payload for _row, payload, _output, _digest in base)
    dtbo_image = pack_dtbo(overlays)
    dtb_path = args.out_dir / "h40-dtb.img"
    dtbo_path = args.out_dir / "h40-dtbo.img"
    dtb_path.write_bytes(dtb_image)
    dtbo_path.write_bytes(dtbo_image)
    dtb_digest = sha256(dtb_image)
    dtbo_digest = sha256(dtbo_image)
    if args.mode == "stock":
        if dtb_digest != STOCK_DTB_IMAGE_SHA256:
            raise SystemExit("stock DTB image hash mismatch: {}".format(dtb_digest))
        if dtbo_digest != STOCK_DTBO_TABLE_SHA256:
            raise SystemExit("stock DTBO table hash mismatch: {}".format(dtbo_digest))

    report = {
        "mode": args.mode,
        "dtc": str(args.dtc),
        "source_root": str(source_root),
        "boot_fdt_entry_count": len(base),
        "hardware_base_variant_count": len(base) - 1,
        "overlay_entry_count": len(overlays),
        "wave16_ddr_stats_required": args.require_wave16_ddr_stats,
        "dtb_image": {
            "file": str(dtb_path),
            "size": len(dtb_image),
            "sha256": dtb_digest,
        },
        "dtbo_image": {
            "file": str(dtbo_path),
            "size": len(dtbo_image),
            "sha256": dtbo_digest,
        },
        "boot_fdt_entries": [
            {
                "index": int(row["index"]),
                "file": str(output),
                "size": len(payload),
                "sha256": digest,
            }
            for row, payload, output, digest in base
        ],
        "overlay_entries": [
            {
                "index": int(row["index"]),
                "file": str(output),
                "size": len(payload),
                "sha256": digest,
            }
            for row, payload, output, digest in overlays
        ],
    }
    report_path = args.out_dir / "reconstruction-report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        "H.40 device trees: PASS ({} boot FDTs: {} base + RTIC; {} overlays; mode={})".format(
            len(base), len(base) - 1, len(overlays), args.mode
        )
    )
    print("DTB  {}  {}".format(dtb_digest, dtb_path))
    print("DTBO {}  {}".format(dtbo_digest, dtbo_path))


if __name__ == "__main__":
    main()
