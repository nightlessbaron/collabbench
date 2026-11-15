import pytest

from codec.decoder import decode
from codec.encoder import encode
from codec.errors import ChecksumError, FrameError

VECTORS = [
    ({'type': 'status', 'qty': 59806, 'offset': 643127324, 'bid': -1838314961, 'tag': 'EN$BW9X'}, 'eae45c5712009ee91c5855262f8a6d92454e240442573958001323'),
    ({'type': 'ping', 'tick': 4195063640, 'slot': 100, 'zone': 'SXS9'}, 'eae45c1c0a0058970bfa645358533900c923'),
    ({'type': 'quote', 'route': 1760533585, 'weight': 53539}, 'eae45c2e0600519cef682403d1d723'),
    ({'type': 'status', 'qty': 61038, 'offset': 2157835873, 'bid': -842201846, 'tag': 'RVLN4YJ'}, 'eae45c5712006eee61f69d800a05cdcd52564c4e34594a00a423'),
    ({'type': 'ping', 'tick': 1092559627, 'slot': 217, 'zone': '9VM438ML'}, 'eae45c1c0e000b24031f41d939564d3433384d4c005423'),
    ({'type': 'quote', 'route': 1600532108, 'weight': 32447}, 'eae45c2e06008c2e665fbf7e6023'),
]

ROUND_TRIP = [
    {'type': 'status', 'qty': 9221, 'offset': 1050136300, 'bid': -2096349912, 'tag': 'L5'},
    {'type': 'ping', 'tick': 33302928, 'slot': 61, 'zone': 'MKXR6QDF'},
    {'type': 'quote', 'route': 2576700283, 'weight': 48338},
    {'type': 'ping', 'tick': 1276548941, 'slot': 35, 'zone': 'BETE8Z'},
    {'type': 'status', 'qty': 55844, 'offset': 2531680555, 'bid': -814897004, 'tag': '4PZEL'},
    {'type': 'quote', 'route': 2358165014, 'weight': 20874},
    {'type': 'quote', 'route': 2531490215, 'weight': 11292},
    {'type': 'ping', 'tick': 2924974216, 'slot': 51, 'zone': '9BD'},
    {'type': 'ping', 'tick': 785499643, 'slot': 138, 'zone': '3V$B9XL'},
    {'type': 'ping', 'tick': 910642213, 'slot': 123, 'zone': 'NR'},
    {'type': 'ping', 'tick': 1681121881, 'slot': 155, 'zone': 'JN$XTVPEMP'},
    {'type': 'status', 'qty': 8351, 'offset': 75035380, 'bid': -2038866653, 'tag': 'ZD'},
    {'type': 'quote', 'route': 3051750662, 'weight': 12323},
    {'type': 'ping', 'tick': 592245016, 'slot': 71, 'zone': 'TG5'},
    {'type': 'quote', 'route': 839896792, 'weight': 22074},
    {'type': 'status', 'qty': 48185, 'offset': 2435001714, 'bid': -1633287563, 'tag': 'WEH99UG9J'},
    {'type': 'ping', 'tick': 611168872, 'slot': 157, 'zone': 'N5JM'},
    {'type': 'status', 'qty': 41409, 'offset': 1927269490, 'bid': -140354524, 'tag': 'EKLUGRQ6X'},
    {'type': 'ping', 'tick': 1299647659, 'slot': 168, 'zone': 'KXD7G'},
    {'type': 'status', 'qty': 51617, 'offset': 2172494149, 'bid': -2015812662, 'tag': '8XVYH3'},
    {'type': 'ping', 'tick': 2789987352, 'slot': 89, 'zone': 'TBP'},
    {'type': 'quote', 'route': 3831773447, 'weight': 35876},
    {'type': 'quote', 'route': 4153769494, 'weight': 17041},
    {'type': 'status', 'qty': 4269, 'offset': 1784882088, 'bid': -1419123963, 'tag': '9UUCQX8A'},
    {'type': 'status', 'qty': 24642, 'offset': 602531075, 'bid': -1549569657, 'tag': 'AH4PP3'},
    {'type': 'status', 'qty': 51363, 'offset': 4467701, 'bid': -1928301150, 'tag': 'A6A'},
    {'type': 'ping', 'tick': 3875505755, 'slot': 130, 'zone': '6A33YZNC'},
    {'type': 'quote', 'route': 1950397435, 'weight': 41883},
    {'type': 'status', 'qty': 19390, 'offset': 3003511274, 'bid': 595613058, 'tag': 'U59D9X'},
    {'type': 'ping', 'tick': 2569291533, 'slot': 70, 'zone': 'L7YUN2H'},
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
