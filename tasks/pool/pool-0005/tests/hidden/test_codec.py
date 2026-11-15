import pytest

from codec.decoder import decode
from codec.encoder import encode
from codec.errors import ChecksumError, FrameError

VECTORS = [
    ({'type': 'status', 'priority': 14240, 'bid': 962143128, 'offset': -1732381027, 'label': 'AT8SDLC'}, 'eeb75968001237a0395924339898bdf69d41543853444c43005023'),
    ({'type': 'reject', 'price': 3267434935, 'batch': 109, 'note': 'YRQ8B8'}, 'eeb7595a000cc2c119b76d595251384238001423'),
    ({'type': 'order', 'account': 2778888010, 'seq': 9024}, 'eeb759460006a5a2774a2433402323'),
    ({'type': 'status', 'priority': 8008, 'bid': 724427171, 'offset': -110174026, 'label': 'DF727SJL'}, 'eeb7596800131f482b2de1a3f96ee0b64446373237534a4c00a923'),
    ({'type': 'reject', 'price': 2921598066, 'batch': 37, 'note': 'X96J'}, 'eeb7595a000aae24340c72255839364a005c23'),
    ({'type': 'order', 'account': 3760123343, 'seq': 56667}, 'eeb759460006e01eedcfdd5ba223'),
]

ROUND_TRIP = [
    {'type': 'order', 'account': 676000128, 'seq': 36776},
    {'type': 'order', 'account': 3721119882, 'seq': 13058},
    {'type': 'reject', 'price': 3528022352, 'batch': 220, 'note': 'Y8XLHEF2'},
    {'type': 'status', 'priority': 23116, 'bid': 2755991660, 'offset': -424985986, 'label': 'QX28J'},
    {'type': 'order', 'account': 3779802752, 'seq': 9117},
    {'type': 'order', 'account': 592606162, 'seq': 54948},
    {'type': 'order', 'account': 3807447816, 'seq': 58404},
    {'type': 'status', 'priority': 38446, 'bid': 1987144065, 'offset': -46323677, 'label': 'TNRVYVWE'},
    {'type': 'reject', 'price': 2246174312, 'batch': 233, 'note': 'B5VY6B'},
    {'type': 'order', 'account': 2224595941, 'seq': 884},
    {'type': 'order', 'account': 2200332706, 'seq': 6436},
    {'type': 'status', 'priority': 6772, 'bid': 1314506731, 'offset': -1878977895, 'label': '6JJ4ACJM4'},
    {'type': 'order', 'account': 871387418, 'seq': 37156},
    {'type': 'order', 'account': 3654362390, 'seq': 8631},
    {'type': 'status', 'priority': 29393, 'bid': 3264017615, 'offset': -83950026, 'label': 'NP5B46'},
    {'type': 'status', 'priority': 25568, 'bid': 414341509, 'offset': -2076853981, 'label': 'R8YAGSW7'},
    {'type': 'status', 'priority': 27083, 'bid': 3215035025, 'offset': -45226268, 'label': 'YZ2YR'},
    {'type': 'status', 'priority': 24190, 'bid': 3520621701, 'offset': -1172587432, 'label': 'V9PQFL'},
    {'type': 'reject', 'price': 1819040762, 'batch': 200, 'note': '9B6ZKV'},
    {'type': 'reject', 'price': 3467619023, 'batch': 101, 'note': '4T675BRF'},
    {'type': 'status', 'priority': 29124, 'bid': 2818538794, 'offset': -2054708457, 'label': 'TUGK'},
    {'type': 'status', 'priority': 62551, 'bid': 256449612, 'offset': -458684989, 'label': 'RHRD853U'},
    {'type': 'order', 'account': 385319945, 'seq': 60045},
    {'type': 'status', 'priority': 61674, 'bid': 3927210187, 'offset': -1569844113, 'label': 'QLH'},
    {'type': 'status', 'priority': 25569, 'bid': 1270256838, 'offset': 1780783668, 'label': 'R5'},
    {'type': 'reject', 'price': 2539867218, 'batch': 232, 'note': 'YG'},
    {'type': 'reject', 'price': 874801936, 'batch': 26, 'note': 'ET5BW'},
    {'type': 'status', 'priority': 43075, 'bid': 4135582847, 'offset': -984145315, 'label': 'KGNEV2T'},
    {'type': 'order', 'account': 1691414979, 'seq': 9359},
    {'type': 'reject', 'price': 918355692, 'batch': 83, 'note': 'GGHBFE'},
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
