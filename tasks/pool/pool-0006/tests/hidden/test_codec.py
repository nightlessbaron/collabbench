import pytest

from codec.decoder import decode
from codec.encoder import encode
from codec.errors import ChecksumError, FrameError

VECTORS = [
    ({'type': 'fill', 'account': 40040, 'tick': 587531900, 'batch': -1020993483, 'symbol': 'RLJ5BX'}, 'e78151591100689c7c0605240335e02404c306524c4a3542580e23'),
    ({'type': 'status', 'seq': 673954144, 'venue': 133, 'zone': 'CLTDWG'}, 'e78151320c0060b92b288506434c54445747a923'),
    ({'type': 'cancel', 'bid': 3676121162, 'route': 9053}, 'e781514606004a281ddb5d24033523'),
    ({'type': 'fill', 'account': 54295, 'tick': 2203337532, 'batch': -527142186, 'symbol': 'U7UWYFARW'}, 'e7815159140017d43c435483d67294e009553755575946415257e223'),
    ({'type': 'status', 'seq': 2526616928, 'venue': 36, 'zone': 'B7'}, 'e78151320800601d999624040242376123'),
    ({'type': 'cancel', 'bid': 3390306563, 'route': 40961}, 'e7815146060003f913ca01a05b23'),
]

ROUND_TRIP = [
    {'type': 'cancel', 'bid': 617330479, 'route': 40647},
    {'type': 'cancel', 'bid': 100664612, 'route': 54542},
    {'type': 'cancel', 'bid': 1992957721, 'route': 40264},
    {'type': 'cancel', 'bid': 620081467, 'route': 5770},
    {'type': 'fill', 'account': 40834, 'tick': 617616681, 'batch': -2080625666, 'symbol': 'L22Y6'},
    {'type': 'fill', 'account': 19818, 'tick': 1102515010, 'batch': -1960300105, 'symbol': 'CQ#Z'},
    {'type': 'cancel', 'bid': 1659142977, 'route': 44848},
    {'type': 'status', 'seq': 2890227323, 'venue': 36, 'zone': 'WCFBTLR'},
    {'type': 'status', 'seq': 314892786, 'venue': 199, 'zone': 'S795'},
    {'type': 'cancel', 'bid': 2905676763, 'route': 59573},
    {'type': 'fill', 'account': 9135, 'tick': 4231478888, 'batch': -1565751704, 'symbol': 'S79ZGL'},
    {'type': 'status', 'seq': 1979240356, 'venue': 35, 'zone': 'CS'},
    {'type': 'cancel', 'bid': 4029125113, 'route': 15108},
    {'type': 'status', 'seq': 3318095610, 'venue': 217, 'zone': 'GT'},
    {'type': 'cancel', 'bid': 1948564670, 'route': 45708},
    {'type': 'fill', 'account': 23279, 'tick': 2808620902, 'batch': -1282258104, 'symbol': 'B59QZ9'},
    {'type': 'fill', 'account': 265, 'tick': 1943976485, 'batch': -1907686176, 'symbol': '5DAH5TLG'},
    {'type': 'status', 'seq': 611391334, 'venue': 221, 'zone': 'WTDREP'},
    {'type': 'status', 'seq': 2764198088, 'venue': 169, 'zone': '8H'},
    {'type': 'fill', 'account': 52148, 'tick': 3908170923, 'batch': -1576237019, 'symbol': 'KXDJE5AJZ'},
    {'type': 'status', 'seq': 4163104708, 'venue': 168, 'zone': 'B56'},
    {'type': 'cancel', 'bid': 1098585718, 'route': 43626},
    {'type': 'fill', 'account': 16737, 'tick': 3200819409, 'batch': -453042824, 'symbol': '75YA4NC'},
    {'type': 'cancel', 'bid': 1914887781, 'route': 23461},
    {'type': 'status', 'seq': 535181381, 'venue': 77, 'zone': '7YCP'},
    {'type': 'fill', 'account': 14016, 'tick': 1076153998, 'batch': -1548916505, 'symbol': '7HNVA8TZD'},
    {'type': 'fill', 'account': 59496, 'tick': 1480438986, 'batch': -790787055, 'symbol': 'QT$EJTEXY'},
    {'type': 'cancel', 'bid': 133345621, 'route': 9191},
    {'type': 'fill', 'account': 38976, 'tick': 757938600, 'batch': -165350194, 'symbol': '695M25'},
    {'type': 'status', 'seq': 316912298, 'venue': 194, 'zone': 'YHF7VRX8K'},
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
