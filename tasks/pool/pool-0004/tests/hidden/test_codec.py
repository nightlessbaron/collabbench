import pytest

from codec.decoder import decode
from codec.encoder import encode
from codec.errors import ChecksumError, FrameError

VECTORS = [
    ({'type': 'quote', 'price': 9754, 'batch': 2326636685, 'offset': -379034781, 'label': 'A8'}, 'aacd5728000d25061a8aada88de96863630241381b26'),
    ({'type': 'ping', 'lot': 975588900, 'venue': 92, 'desk': 'TBAU'}, 'aacd575e000a3a25064e245c04544241555f26'),
    ({'type': 'order', 'route': 1199384158, 'priority': -128367603}, 'aacd57270008477d25065ef859440d9f26'),
    ({'type': 'quote', 'price': 26044, 'batch': 1025453239, 'offset': -1626448070, 'label': '4GBQ4'}, 'aacd5728001065bc3d1f2cb79f0e5f3a053447425134d326'),
    ({'type': 'ping', 'lot': 640740342, 'venue': 156, 'desk': '9QFSBRJ'}, 'aacd575e000d250630ebf69c073951465342524a1026'),
    ({'type': 'order', 'route': 220260393, 'priority': -1437979935}, 'aacd572700080d20e829aa4a2ae1c226'),
]

ROUND_TRIP = [
    {'type': 'ping', 'lot': 645575815, 'venue': 147, 'desk': 'SPBKLDE'},
    {'type': 'ping', 'lot': 4282341842, 'venue': 75, 'desk': 'VF8MN'},
    {'type': 'quote', 'price': 46204, 'batch': 3278639393, 'offset': -99744905, 'label': '5VTH'},
    {'type': 'quote', 'price': 35541, 'batch': 876180146, 'offset': -1619766298, 'label': '3J'},
    {'type': 'quote', 'price': 10421, 'batch': 463686940, 'offset': -847793208, 'label': 'L6FAD3XR'},
    {'type': 'order', 'route': 932166497, 'priority': -1685196724},
    {'type': 'ping', 'lot': 1579072920, 'venue': 206, 'desk': 'TJ3'},
    {'type': 'quote', 'price': 6583, 'batch': 132018075, 'offset': -1898133232, 'label': '39LT9XXK'},
    {'type': 'ping', 'lot': 1415537638, 'venue': 139, 'desk': '6K54936'},
    {'type': 'ping', 'lot': 3424563520, 'venue': 164, 'desk': 'AUAGF'},
    {'type': 'quote', 'price': 29542, 'batch': 2711405378, 'offset': -1126237218, 'label': '8L3RD'},
    {'type': 'ping', 'lot': 1465041660, 'venue': 125, 'desk': 'EC'},
    {'type': 'quote', 'price': 55722, 'batch': 3183447987, 'offset': -1973157338, 'label': 'TZCYDT'},
    {'type': 'order', 'route': 1975985854, 'priority': -1666273692},
    {'type': 'ping', 'lot': 924764237, 'venue': 236, 'desk': '5KMCME8K'},
    {'type': 'order', 'route': 2535790534, 'priority': -544380413},
    {'type': 'ping', 'lot': 1743068567, 'venue': 43, 'desk': '2ATMWRTB'},
    {'type': 'quote', 'price': 60919, 'batch': 3181259498, 'offset': -1776548913, 'label': 'RMEYE2'},
    {'type': 'order', 'route': 1403978083, 'priority': -1960431496},
    {'type': 'ping', 'lot': 1497679870, 'venue': 69, 'desk': 'VS%S56US6'},
    {'type': 'quote', 'price': 11354, 'batch': 3033341844, 'offset': -1712233167, 'label': 'VL34'},
    {'type': 'order', 'route': 1867634407, 'priority': -2109240833},
    {'type': 'ping', 'lot': 4049570665, 'venue': 38, 'desk': 'GVR8MG5'},
    {'type': 'order', 'route': 3417958208, 'priority': -1948389916},
    {'type': 'ping', 'lot': 2881078162, 'venue': 1, 'desk': 'UUATF7S'},
    {'type': 'quote', 'price': 18555, 'batch': 1218410169, 'offset': -236606873, 'label': 'ZBWWQTW'},
    {'type': 'order', 'route': 796843877, 'priority': -1476476981},
    {'type': 'ping', 'lot': 4028281364, 'venue': 212, 'desk': 'HW2WA'},
    {'type': 'ping', 'lot': 3901278442, 'venue': 204, 'desk': 'KPXT6L9Z'},
    {'type': 'order', 'route': 2728129668, 'priority': -1703729570},
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
