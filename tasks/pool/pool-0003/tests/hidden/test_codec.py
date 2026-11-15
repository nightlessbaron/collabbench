import pytest

from codec.decoder import decode
from codec.encoder import encode
from codec.errors import ChecksumError, FrameError

VECTORS = [
    ({'type': 'order', 'slot': 27004, 'priority': 2742259188, 'seq': -1510310391, 'label': '9YWE7KU'}, '83e6453d12007c69f48d73a3097d6efaa539595745374b5500d47e'),
    ({'type': 'fill', 'offset': 180794929, 'lot': 40, 'symbol': 'TMZ'}, '83e64556090031b6c60a28544d5a00787e'),
    ({'type': 'status', 'weight': 4000520931, 'venue': 2120123829}, '83e645580800e31a73eeb5855e7d6e627e'),
    ({'type': 'order', 'slot': 8492, 'priority': 694682585, 'seq': -1010170766, 'label': 'S5'}, '83e6453d0d002c21d90368297204cac3533500d07e'),
    ({'type': 'fill', 'offset': 224716379, 'lot': 126, 'symbol': '476C'}, '83e645560a005be6640d7d6e34373643008e7e'),
    ({'type': 'status', 'weight': 1630344051, 'venue': -1524124336}, '83e64558080073132d6150b527a54a7e'),
]

ROUND_TRIP = [
    {'type': 'status', 'weight': 2357600362, 'venue': -2053733482},
    {'type': 'order', 'slot': 60578, 'priority': 3280113856, 'seq': -546948499, 'label': 'F6EXTM3'},
    {'type': 'fill', 'offset': 4028203062, 'lot': 172, 'symbol': '3XUSLK'},
    {'type': 'fill', 'offset': 2117432851, 'lot': 252, 'symbol': '58E5E'},
    {'type': 'order', 'slot': 40268, 'priority': 3037862690, 'seq': -88253, 'label': '6UVQ25L8'},
    {'type': 'order', 'slot': 27780, 'priority': 245806078, 'seq': -1625024799, 'label': 'M7PGL'},
    {'type': 'fill', 'offset': 820713817, 'lot': 242, 'symbol': 'RE89K3L'},
    {'type': 'status', 'weight': 1430408269, 'venue': 1349602173},
    {'type': 'status', 'weight': 355787233, 'venue': -131840643},
    {'type': 'fill', 'offset': 343806333, 'lot': 109, 'symbol': 'MM'},
    {'type': 'status', 'weight': 2804027751, 'venue': -1914432407},
    {'type': 'status', 'weight': 1797358251, 'venue': -360510973},
    {'type': 'status', 'weight': 813701919, 'venue': 2124063584},
    {'type': 'status', 'weight': 1738781431, 'venue': -1199765333},
    {'type': 'order', 'slot': 62812, 'priority': 2496797559, 'seq': -1648057024, 'label': 'KD~UWV'},
    {'type': 'status', 'weight': 2515285327, 'venue': -348191842},
    {'type': 'status', 'weight': 1187171770, 'venue': -657893342},
    {'type': 'order', 'slot': 62494, 'priority': 2769586628, 'seq': -2137698567, 'label': 'BE~TCC6WZ'},
    {'type': 'order', 'slot': 44773, 'priority': 1996516362, 'seq': -1550251700, 'label': 'QE'},
    {'type': 'order', 'slot': 61821, 'priority': 4029968370, 'seq': -1667317082, 'label': 'X6A'},
    {'type': 'status', 'weight': 823461578, 'venue': 2111210474},
    {'type': 'fill', 'offset': 728748245, 'lot': 108, 'symbol': 'DG}DQ'},
    {'type': 'order', 'slot': 22609, 'priority': 1230897857, 'seq': 2102208779, 'label': 'V2XTLXW'},
    {'type': 'fill', 'offset': 3275200608, 'lot': 59, 'symbol': 'XQ37SYRD8'},
    {'type': 'fill', 'offset': 193571355, 'lot': 77, 'symbol': 'SERKUPT'},
    {'type': 'status', 'weight': 1880005381, 'venue': -1441901239},
    {'type': 'fill', 'offset': 1228444264, 'lot': 230, 'symbol': '44~TWQ4JT'},
    {'type': 'order', 'slot': 54821, 'priority': 3785760637, 'seq': -1894130510, 'label': 'S5'},
    {'type': 'order', 'slot': 48439, 'priority': 770593009, 'seq': -434876677, 'label': 'ZNCQ5MLCJ'},
    {'type': 'status', 'weight': 4120913698, 'venue': -1580014454},
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
