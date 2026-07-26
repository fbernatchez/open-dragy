"""Send UBX CFG for NAV-PVT @ 10 Hz through SerialToSerial bridge on COM5."""

from __future__ import annotations

import struct
import sys
import time

import serial

PORT = "COM5"
BAUD = 115200


def ubx_packet(cls: int, msg_id: int, payload: bytes) -> bytes:
    hdr = bytes([cls, msg_id, len(payload) & 0xFF, (len(payload) >> 8) & 0xFF])
    body = hdr + payload
    cka = ckb = 0
    for b in body:
        cka = (cka + b) & 0xFF
        ckb = (ckb + cka) & 0xFF
    return b"\xb5\x62" + body + bytes([cka, ckb])


def cfg_valset(key: int, value: bytes, layers: int = 0x07) -> bytes:
    # version=0, layers, reserved0, reserved1, key LE, value
    payload = bytes([0x00, layers, 0x00, 0x00]) + struct.pack("<I", key) + value
    return ubx_packet(0x06, 0x8A, payload)


def cfg_msg_nav_pvt_uart1(rate: int = 1) -> bytes:
    # class=NAV(0x01), id=PVT(0x07), rates for I2C,UART1,UART2,USB,SPI,reserved
    payload = bytes([0x01, 0x07, 0x00, rate, 0x00, 0x00, 0x00, 0x00])
    return ubx_packet(0x06, 0x01, payload)


def parse_acks(buf: bytes) -> list[tuple[str, int, int]]:
    """Return list of (ACK|NAK, cls, id) from buffer."""
    out = []
    i = 0
    while True:
        j = buf.find(b"\xb5\x62", i)
        if j < 0 or j + 10 > len(buf):
            break
        cls = buf[j + 2]
        mid = buf[j + 3]
        plen = buf[j + 4] | (buf[j + 5] << 8)
        end = j + 6 + plen + 2
        if end > len(buf):
            break
        if cls == 0x05 and plen >= 2:
            ack_cls = buf[j + 6]
            ack_id = buf[j + 7]
            kind = "ACK" if mid == 0x01 else "NAK" if mid == 0x00 else f"ACK?{mid:02X}"
            out.append((kind, ack_cls, ack_id))
        i = j + 2
    return out


def count_nav_pvt(buf: bytes) -> int:
    n = 0
    i = 0
    while True:
        j = buf.find(b"\xb5\x62\x01\x07", i)
        if j < 0:
            break
        n += 1
        i = j + 4
    return n


def drain(ser: serial.Serial, seconds: float) -> bytes:
    end = time.time() + seconds
    data = b""
    while time.time() < end:
        chunk = ser.read(4096)
        if chunk:
            data += chunk
        else:
            time.sleep(0.01)
    return data


def send_and_wait(ser: serial.Serial, pkt: bytes, label: str, wait_s: float = 0.35) -> str:
    # Clear a bit of RX so ACK is easier to spot
    ser.reset_input_buffer()
    ser.write(pkt)
    ser.flush()
    time.sleep(0.05)
    resp = drain(ser, wait_s)
    acks = parse_acks(resp)
    if not acks:
        print(f"  {label}: no ACK/NAK (rx={len(resp)} B)")
        return "NONE"
    # Prefer last matching CFG
    for kind, cls, mid in acks:
        print(f"  {label}: {kind} for {cls:02X}/{mid:02X} (rx={len(resp)} B)")
    return acks[-1][0]


def main() -> int:
    print(f"Opening {PORT} @ {BAUD} ...")
    try:
        ser = serial.Serial(PORT, BAUD, timeout=0.05)
    except Exception as e:
        print("OPEN_FAIL", e)
        return 2

    ser.dtr = False
    ser.rts = False
    time.sleep(0.8)

    baseline = drain(ser, 1.0)
    ubx_sync = bytes([0xB5, 0x62])
    print(
        f"Baseline: {len(baseline)} B, NMEA$={baseline.count(b'$')}, "
        f"UBX={baseline.count(ubx_sync)}, NAV-PVT={count_nav_pvt(baseline)}"
    )

    # layers: RAM|BBR|Flash — if Flash NAKs, retry RAM-only below
    layers = 0x07

    commands: list[tuple[str, bytes]] = [
        ("UART1OUTPROT-UBX=1", cfg_valset(0x10740001, bytes([1]), layers)),
        ("UART1OUTPROT-NMEA=1", cfg_valset(0x10740002, bytes([1]), layers)),
        ("UART1INPROT-UBX=1", cfg_valset(0x10730001, bytes([1]), layers)),
        ("UART1INPROT-NMEA=1", cfg_valset(0x10730002, bytes([1]), layers)),
        ("RATE-MEAS=100ms", cfg_valset(0x30210001, struct.pack("<H", 100), layers)),
        ("RATE-NAV=1", cfg_valset(0x30210002, struct.pack("<H", 1), layers)),
        ("DYNMODEL=Automotive", cfg_valset(0x20110021, bytes([4]), layers)),
        ("MSGOUT-NAV_PVT_UART1=1", cfg_valset(0x20910007, bytes([1]), layers)),
        ("CFG-MSG NAV-PVT UART1=1", cfg_msg_nav_pvt_uart1(1)),
        ("NMEA-GGA=1", cfg_valset(0x209100ba, bytes([1]), layers)),
        ("NMEA-RMC=1", cfg_valset(0x209100ac, bytes([1]), layers)),
        ("NMEA-VTG=0", cfg_valset(0x209100b1, bytes([0]), layers)),
        ("NMEA-GSA=0", cfg_valset(0x209100c0, bytes([0]), layers)),
        ("NMEA-GSV=0", cfg_valset(0x209100c5, bytes([0]), layers)),
        ("NMEA-GLL=0", cfg_valset(0x209100ca, bytes([0]), layers)),
        # Multi-GNSS + SBAS
        ("GPS-L1CA=1", cfg_valset(0x1031001F, bytes([1]), layers)),
        ("GPS-L1CA ena signal", cfg_valset(0x10310001, bytes([1]), layers)),
        ("GAL-E1=1", cfg_valset(0x10310021, bytes([1]), layers)),
        ("GAL ena", cfg_valset(0x10310007, bytes([1]), layers)),
        ("BDS-B1=1", cfg_valset(0x10310025, bytes([1]), layers)),
        ("BDS ena", cfg_valset(0x1031000A, bytes([1]), layers)),
        ("GLO-L1=1", cfg_valset(0x10310022, bytes([1]), layers)),
        ("GLO ena", cfg_valset(0x1031000D, bytes([1]), layers)),
        ("SBAS-L1CA=1", cfg_valset(0x10310020, bytes([1]), layers)),
        ("SBAS ena", cfg_valset(0x10310005, bytes([1]), layers)),
        ("SBAS-USE_TESTMODE=1", cfg_valset(0x10360002, bytes([1]), layers)),
        ("SBAS-USE_DIFFCORR=1", cfg_valset(0x10360004, bytes([1]), layers)),
    ]

    print(f"Sending {len(commands)} CFG commands (layers=RAM+BBR+Flash)...")
    ack_n = nak_n = none_n = 0
    for label, pkt in commands:
        result = send_and_wait(ser, pkt, label)
        if result == "ACK":
            ack_n += 1
        elif result == "NAK":
            nak_n += 1
        else:
            none_n += 1
        time.sleep(0.08)

    print(f"Summary: ACK={ack_n} NAK={nak_n} NONE={none_n}")

    print("Waiting 3 s for NAV-PVT...")
    after = drain(ser, 3.0)
    pvt = count_nav_pvt(after)
    ubx = after.count(ubx_sync)
    print(f"After: {len(after)} B, UBX sync={ubx}, NAV-PVT frames={pvt}, NMEA$={after.count(b'$')}")

    if pvt > 0:
        print("SUCCESS: NAV-PVT is flowing.")
        rc = 0
    elif ack_n > 0:
        print("PARTIAL: got ACKs but no NAV-PVT yet — retry or check keys.")
        rc = 1
    else:
        print("FAIL: no ACK and no NAV-PVT. Bridge may not be forwarding TX, or GPS ignores UBX.")
        # Retry critical PVT enables on RAM-only
        print("Retry RAM-only PVT enable...")
        for label, key, val in [
            ("RAM UART1OUTPROT-UBX", 0x10740001, bytes([1])),
            ("RAM MSGOUT-NAV_PVT", 0x20910007, bytes([1])),
        ]:
            send_and_wait(ser, cfg_valset(key, val, 0x01), label, wait_s=0.5)
        send_and_wait(ser, cfg_msg_nav_pvt_uart1(1), "RAM CFG-MSG NAV-PVT", wait_s=0.5)
        after2 = drain(ser, 3.0)
        pvt2 = count_nav_pvt(after2)
        print(f"Retry after: NAV-PVT={pvt2}, UBX={after2.count(ubx_sync)}")
        rc = 0 if pvt2 > 0 else 1

    ser.close()
    return rc


if __name__ == "__main__":
    sys.exit(main())
