import pytest

from codec.decoder import decode
from codec.encoder import encode
from codec.errors import ChecksumError, FrameError

VECTORS = [
    ({'type': 'status', 'lot': 1926, 'weight': 980165968, 'slot': -748321463, 'desk': 'KR\\J'}, 'f5bd46260f00860750256c3a498565d3044b525c7c4afb5e'),
    ({'type': 'fill', 'bid': 3572329662, 'offset': 129, 'zone': 'KUB'}, 'f5bd46350900be6cedd481034b5542ab5e'),
    ({'type': 'ping', 'tick': 3789774942, 'price': 14598}, 'f5bd464a06005c7e60e3e10639e85e'),
    ({'type': 'status', 'lot': 25005, 'weight': 519549379, 'slot': -1920884620, 'desk': 'CA2UDQXBS'}, 'f5bd46261400ad61c3b1f71e74a0818d09434132554451584253315e'),
    ({'type': 'fill', 'bid': 477305904, 'offset': 94, 'zone': 'KS'}, 'f5bd46350800301c731c5c7e024b53ef5e'),
    ({'type': 'ping', 'tick': 199074180, 'price': 45014}, 'f5bd464a060084a1dd0bd6afb95e'),
]

ROUND_TRIP = [
    {'type': 'status', 'lot': 39285, 'weight': 4111553517, 'slot': 1583418382, 'desk': 'VTD'},
    {'type': 'fill', 'bid': 114737068, 'offset': 252, 'zone': 'EBP'},
    {'type': 'status', 'lot': 58056, 'weight': 1642674843, 'slot': -1566177046, 'desk': 'WYDR'},
    {'type': 'status', 'lot': 59263, 'weight': 1948852998, 'slot': -1931364568, 'desk': '8D6TFY6G'},
    {'type': 'fill', 'bid': 1240416182, 'offset': 233, 'zone': 'B2T'},
    {'type': 'fill', 'bid': 1290336092, 'offset': 163, 'zone': '73QZGM8'},
    {'type': 'ping', 'tick': 1552405395, 'price': 30439},
    {'type': 'status', 'lot': 55175, 'weight': 1555934340, 'slot': -2064522147, 'desk': 'JFPS'},
    {'type': 'ping', 'tick': 2429823087, 'price': 3085},
    {'type': 'ping', 'tick': 2304854754, 'price': 13150},
    {'type': 'fill', 'bid': 806337403, 'offset': 94, 'zone': 'R8'},
    {'type': 'status', 'lot': 38543, 'weight': 3251462109, 'slot': -1614354659, 'desk': '4N^45'},
    {'type': 'fill', 'bid': 1948016133, 'offset': 87, 'zone': 'EHN9MFGBZ'},
    {'type': 'status', 'lot': 45321, 'weight': 4158438434, 'slot': -606160897, 'desk': 'CN\\G'},
    {'type': 'status', 'lot': 49281, 'weight': 1199765281, 'slot': 1553448075, 'desk': '46Q9B99'},
    {'type': 'status', 'lot': 53122, 'weight': 71878904, 'slot': -296204120, 'desk': 'F9ATSUQA'},
    {'type': 'fill', 'bid': 3960035142, 'offset': 27, 'zone': 'CERM5ALR'},
    {'type': 'status', 'lot': 22842, 'weight': 1071980924, 'slot': -619931998, 'desk': 'VU2'},
    {'type': 'fill', 'bid': 480723408, 'offset': 150, 'zone': '8H^D647L7'},
    {'type': 'ping', 'tick': 144667228, 'price': 23088},
    {'type': 'fill', 'bid': 2991385567, 'offset': 94, 'zone': '8BG'},
    {'type': 'ping', 'tick': 500642542, 'price': 9568},
    {'type': 'fill', 'bid': 2791079132, 'offset': 106, 'zone': '7CCUP6'},
    {'type': 'status', 'lot': 1321, 'weight': 3671848053, 'slot': -1484544347, 'desk': 'Y2V6SM2SK'},
    {'type': 'fill', 'bid': 2593406373, 'offset': 87, 'zone': 'N7QDRL'},
    {'type': 'fill', 'bid': 735151789, 'offset': 183, 'zone': 'SLYZAL6'},
    {'type': 'status', 'lot': 20900, 'weight': 1208130677, 'slot': -1826990225, 'desk': '4G^DASDFX'},
    {'type': 'status', 'lot': 40598, 'weight': 3761137469, 'slot': -173251819, 'desk': 'NFL824XW'},
    {'type': 'status', 'lot': 23495, 'weight': 3043143057, 'slot': -1271546058, 'desk': 'DFGU'},
    {'type': 'ping', 'tick': 2259442529, 'price': 20979},
]


@pytest.mark.parametrize("i", range(len(VECTORS)))
def test_R1_encode(i):
    msg, frame = VECTORS[i]
    assert encode(dict(msg)) == bytes.fromhex(frame)


@pytest.mark.parametrize("i", range(len(VECTORS)))
def test_R2_decode(i):
    msg, frame = VECTORS[i]
    assert decode(bytes.fromhex(frame)) == msg


@pytest.mark.parametrize("i", range(3))
def test_R3_round_trip(i):
    for msg in ROUND_TRIP[i::3]:
        assert decode(encode(dict(msg))) == msg


def _frame():
    return bytearray(bytes.fromhex(VECTORS[1][1]))


def test_R4_bad_checksum():
    frame = _frame()
    frame[-2] ^= 0x01
    with pytest.raises(ChecksumError):
        decode(bytes(frame))


def test_R4_bad_magic():
    frame = _frame()
    frame[0] ^= 0xFF
    with pytest.raises(FrameError):
        decode(bytes(frame))


def test_R4_bad_version():
    frame = _frame()
    frame[2] ^= 0x01
    with pytest.raises(FrameError):
        decode(bytes(frame))
